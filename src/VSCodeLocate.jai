#import "Basic";
#import "Compiler";
#import "Hash_Table";
#import "Machine_X64";
#import "String";

debug :: false;

help_text :: #string __sh
    Usage: jai -import_dir <VSCodeLocate Folder> -meta VSCodeLocate <project.jai> -- <Operation>

    <Operation> is one of:

        Find <file.jai> <row> <col>   # Will return references for token at specified postion.
        Dump                          # Will return references for evey token.
__sh;

sentinel :: "fe955110-fc9e-4c28-be65-93cdffdb26c9";


target_path : string;
target_line : int;
target_char : int;
finished_typechecking := false;
mode : enum { SINGLE_REFERENCE; ALL_REFERENCES; };

get_plugin :: () -> *Metaprogram_Plugin {
  plugin := New(Metaprogram_Plugin);

  plugin.before_intercept = before_intercept;
  plugin.handle_one_option = handle_one_option;
  plugin.message = check_valid_message;
  return plugin;
}

handle_one_option :: (p: *Metaprogram_Plugin, options: [] string, cursor: int) -> (new_cursor: int) {
    new_cursor := cursor;

    operation := options[cursor];
    if operation == "-Find" {
        if options.count < cursor + 4 {
            write_string(help_text);
            exit(1);
        }
        new_cursor = cursor + 4;

        mode = .SINGLE_REFERENCE;
        target_path = options[cursor + 1];
        normalize_path(target_path);


        line_ok, char_ok: bool;

        target_line, line_ok = parse_int(*options[cursor + 2]);
        target_char, char_ok = parse_int(*options[cursor + 3]);

        if !(line_ok && char_ok) {
            write_string(help_text);
            exit(1);
        }
    }
    else if operation == "-Dump" {
        mode = .ALL_REFERENCES;
        new_cursor = cursor + 1;
    }

    return new_cursor;
}

before_intercept :: (p: *Metaprogram_Plugin, flags: *Intercept_Flags) {
    #if debug  print("DEBUG ENABLED\n");
    options := get_build_options(p.workspace);
    options.output_type = .NO_OUTPUT;
    set_build_options(options, p.workspace);
}



identifier : string;

Location_List  :: [..] Source_Code_Range;
locations : Table(*Code_Declaration, Location_List);
expressions : [..] *Code_Node;
to_revisit : [..] *Code_Ident;


check_valid_message :: (p: *Metaprogram_Plugin, message: *Message) {
    if message.kind == {
        case .TYPECHECKED;
        code := cast(*Message_Typechecked) message;
        for typechecked: code.all {
            expr := typechecked.expression;
            array_add(*expressions, expr);
            for typechecked.subexpressions  array_add(*expressions, it);
        }

        case .COMPILATION_PHASE;
        phase := cast (*Message_Phase) message;
        if phase.phase == .TYPECHECKED_ALL_WE_CAN && phase.num_items_waiting_to_typecheck == 0 {
            finished_typechecking = true;

            for expr: expressions
                process_decl_or_ident(expr);

            #if debug {
                for location_list, decl: locations {
                    print("%: % (%)\n", decl.name, format_range(decl), location_list.count);
                    for location_list
                        print(" %\n", format_range(it));
                    print("\n");
                }
            }

            if mode == {
                case .SINGLE_REFERENCE;  // look for ident
                needle := decl_from_location(target_path, target_line, target_char);
                if needle {
                    print(sentinel);
                    needle_range := format_range(needle);
                    print("%|%\n", needle.name, needle_range);
                    ranges, _ := table_find(*locations, needle);
                    for ranges {
                        range := format_range(it);
                        if range != needle_range
                            print("|%\n", range);
                    }
                }

                case .ALL_REFERENCES; // dump everything
                print(sentinel);
                for ranges, needle: locations {
                    needle_range := format_range(needle);
                    print("%|%\n", needle.name, needle_range);
                    for ranges {
                        range := format_range(it);
                        if range != needle_range
                            print("|%\n", range);
                    }
                    print("\n");
                }
            }
        }
    }
}


process_decl_or_ident :: (node: *Code_Node) {
    if node.kind == {
        case .DECLARATION;
        decl := cast(*Code_Declaration) node;
        if !is_valid_decl(decl)  return;
        check_add_decl(decl);

        case .IDENT;
        ident := cast(*Code_Ident) node;
        if ident.name == ""  return;

        decl := ident.resolved_declaration;

        if !is_valid_decl(decl)  return;

        range := make_code_range(ident);

        list := check_add_decl(decl);
        array_add(*list, range);
        table_set(*locations, decl, list);
    }
}


check_add_decl :: (decl: *Code_Declaration) -> Location_List {
    location_list, found := table_find(*locations, decl);
    if found {
        return location_list;
    }
    else {
        location_list : Location_List;
        array_add(*location_list, make_code_range(decl));
        table_set(*locations, decl, location_list);
        return location_list;
    }
}


is_valid_decl :: (decl: *Code_Declaration) -> bool {
    //return decl != null;
    return decl && decl.name != "" && decl.enclosing_load
        && (decl.enclosing_load.enclosing_import.module_type == .MAIN_PROGRAM
            || decl.enclosing_load.enclosing_import.module_type == .FILE);
}


decl_from_location :: (filename: string, line: int, char: int) -> *Code_Declaration {
    for ranges, decl: locations {
        for range: ranges {
            decl_path := copy_string(range.fully_pathed_filename);
            defer free(decl_path);  // @TODO @Speed
            normalize_path(decl_path);
            if decl_path != filename
                continue;

            if line < range.line_number_start || line > range.line_number_end
                continue;

            if line == range.line_number_start && char < range.character_number_start
            || line == range.line_number_end   && char > range.character_number_end
                continue;

            return decl;
        }
    }

    return null;
}



#scope_file



format_location :: (node: *Code_Node) -> string {
    location := make_location(node);
    return sprint("%:%:%", location.fully_pathed_filename, location.line_number, location.character_number);
}


format_range :: (range: Source_Code_Range) -> string {
    return sprint("%|%|%|%|%", range.fully_pathed_filename, range.line_number_start, range.character_number_start, range.line_number_end, range.character_number_end);
}


format_range :: (node: *Code_Node) -> string {
    return format_range(make_code_range(node));
}


make_code_range :: (node: *Code_Node) -> Source_Code_Range {
    range : Source_Code_Range = ---;
    range.fully_pathed_filename  = node.enclosing_load.fully_pathed_filename;
    range.line_number_start      = node.l0;
    range.line_number_end        = ifx node.l1 < 0 then node.l0 else node.l1;
    range.character_number_start = node.c0;

    // @Note c1 for declarations include function signatures, so crop it down
    if node.kind == .DECLARATION {
        decl := cast(*Code_Declaration) node;
        range.character_number_end = range.character_number_start + decl.name.count;
    }
    else
        range.character_number_end = node.c1;

    return range;
}


normalize_path :: (path: string) {
    if path {
        path_overwrite_separators(path);

        for c_index: 0 .. path.count-1 {
            path[c_index] = to_lower(path[c_index]);
        }
    }
}
