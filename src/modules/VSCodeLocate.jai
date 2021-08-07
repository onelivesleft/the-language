#import "Basic";
#import "Compiler";
#import "Hash_Table";
#import "String";

// @TODO When we find an ident declared outwith the main program (i.e. in a module)
//       we just ignore it: we should do something more useful.

debug :: false;

help_text :: "Usage: jai -import_dir <Locate Folder> -meta Locate <project.jai> -- <file.jai> <row> <col>\n";


set_options :: (using options: *Build_Options) {
    emit_debug_info = .NONE;
    output_path = "c:/temp";
    intermediate_path = "c:/temp";
}


test_path :: "c:/repos/jaitest/foo.jai";


target_path : string;
target_line : int;
target_char : int;
finished_typechecking := false;


#run {
    args := compiler_get_command_line_arguments();
    if args.count < 3 {
        print(help_text);
        exit(1);
    }

    line_ok : bool;
    char_ok : bool;

    target_path = args[0];
    normalize_path(target_path);
    target_line, line_ok = parse_int(*args[1]);
    target_char, char_ok = parse_int(*args[2]);
    //target_path = test_path;
    //target_line = 67;
    //target_char = 5;

    if !(line_ok && char_ok) {
        print(help_text);
        exit(1);
    }

    workspace := compiler_create_workspace("Target Program");
    if !workspace {
        print("Workspace creation failed.\n");
        return;
    }

    files, run_strings := compiler_get_source_files();
    if files {
        basename, path := get_basename_and_path(files[0]);
        if path {
            old_wd := get_working_directory();
            set_working_directory(path);

            for * files {
                //print("%\n", it);
                old_filename := <<it;
                if is_absolute_path(old_filename) continue;
                <<it = sprint("%/%", old_wd, old_filename);
            }
        }
    }

    build_options := get_build_options(workspace);
    build_options.output_type = .NO_OUTPUT;
    build_options.emit_debug_info = .NONE;
    build_options.output_path = "c:/temp/"; // @TODO make correct
    build_options.intermediate_path = "c:/temp/";
    //build_options.user_data_u64 = xx *check_message;
    set_build_options(build_options, workspace);

    init(*locations);

    compiler_begin_intercept(workspace);

    for files        add_build_file(it, workspace);
    for run_strings  add_build_string(tprint("#run %;\n", it), workspace);

    while !finished_typechecking {
        message := compiler_wait_for_message();
        valid, complete := my_check_message(message);
        if complete  break;
    }

    compiler_end_intercept(workspace);

    exit(0);

/*
    check_message :: (message: *Message) -> valid: bool, complete: bool {
        if !message return false, false;
        if message.kind == .COMPLETE return false, true;

        handle_message(message, true);

        return true, false;
    }
*/

    my_check_message :: (message: *Message) -> valid: bool, complete: bool {
        if !message return false, false;
        if message.kind == .COMPLETE return false, true;

        handle_message(message);

        return true, false;
    }


    is_absolute_path :: (path: string) -> bool { // This routine is probably not as correct as we'd like. We'd like to put in a better one! But maybe we will stop doing the cwd thing, or do it differently; hard to say.
        if !path return false;

        if path[0] == #char "/" return true;  // Backslashes have already been converted to forward slashes by this point.
        if path.count >= 3 {
            // @Robustness: Check for a drive letter in character 0?  Anything else?
            if path[1] == #char ":" return true;
        }

        return false;
    }
}



identifier : string;

Location_List  :: [..] Source_Code_Range;
locations : Table(*Code_Declaration, Location_List);
expressions : [..] *Code_Node;
to_revisit : [..] *Code_Ident;


handle_message :: (message: *Message) {
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

            // look for ident
            needle := decl_from_location(target_path, target_line, target_char);
            //print("Looking for: %:%:% = %\n", target_path, target_line, target_char, needle);
            if needle {
                needle_range := format_range(needle);
                print("%\n", needle_range);
                ranges, _ := table_find(locations, needle);
                for ranges {
                    range := format_range(it);
                    if range != needle_range
                        print("%\n", range);
                }
            }

            //print("Revisit count: %\n", to_revisit.count);
            ////for to_revisit  print("%\n", format_location(it));
            //for to_revisit  print("%\n", <<it);
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
        //if !decl { // @TODO if we no longer get these (which would be good!) then remove this and add
        //           //       null check to `is_valid_decl`
        //    array_add(*to_revisit, ident);
        //    print("Missing declaration for: %\n%\n\n", ident.name, format_location(ident));
        //    return;
        //}

        if !is_valid_decl(decl)  return;

        range := make_code_range(ident);

        list := check_add_decl(decl);
        array_add(*list, range);
        table_set(*locations, decl, list);
    }
}


check_add_decl :: (decl: *Code_Declaration) -> Location_List {
    location_list, found := table_find(locations, decl);
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
    return decl
        && decl.enclosing_load
        && decl.enclosing_load.enclosing_import.module_type == .MAIN_PROGRAM;
}


decl_from_location :: (filename: string, line: int, char: int) -> *Code_Declaration {
    for ranges, decl: locations {
        decl_path := copy_string(decl.enclosing_load.fully_pathed_filename);
        defer free(decl_path);

        normalize_path(decl_path);
        if decl_path != filename
            continue;

        for range: ranges {
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
    translate_path(path);
    to_lower(path);
}
