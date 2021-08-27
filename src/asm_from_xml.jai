#import "Basic";
#import "File";
#import "Hash_Table";

jai_string :: #import "String";
parse_int :: jai_string.parse_int;

#load "strings.jai";

// @TODO

// [ ] Goto definition on asm operator goes to felix url
// [ ] Better descriptions (e.g. flags written)


in_file           :: "instructions.xml";
//in_file           :: "sample.xml";
out_file          :: "asmCommands.json";

json : String_Builder;

main :: () {
    xml, success := read_entire_file(in_file);
    if !success {
        print("Failed to read %", in_file);
        exit(1);
    }

    init_string_builder(*json);
    append(*json, "{\n");

    instruction_list : [..] Instruction;
    current_instruction : *Instruction;

    for line_raw: split_it(xml, "\n") {
        line := trim(line_raw);
        if starts_with(line, "<instruction") {
            current_instruction = array_add(*instruction_list);
            <<current_instruction = instruction_from_string(line);
            if ends_with(line, "/>")  current_instruction = null;
        }
        if starts_with(line, "<operand") && current_instruction {
            add_operand(current_instruction, operand_from_string(line));
        }
    }

    instructions : Table(string, Table(string, [..] Instruction));
    for instruction: instruction_list {
        assert(instruction.operand_count <= 10, "Max operand count has increased, update the Hash type!");

        variations_table, found_variations := table_find(instructions, instruction.name);
        variations : type_of(variations_table);
        if found_variations  variations = variations_table;

        hash := instruction_hash(instruction);
        hash_string := copy_string(to_string(*hash[0]));
        list, found := table_find(variations, hash_string);
        if found {
            array_add(*list, instruction);
            table_set(*variations, hash_string, list);
        }
        else {
            new_list : [..] Instruction;
            array_add(*new_list, instruction);
            table_set(*variations, hash_string, new_list);
        }

        table_set(*instructions, instruction.name, variations);
    }


    first := true;
    for variations, instruction_name: instructions {
        if !first  append(*json, ",\n");
        else       append(*json, "\n");
        first = false;
        append(*json, "    ");
        name := copy_string(instruction_name);
        to_lower(name);
        count := 0;
        for instruction_array, hash: variations {
            instruction := instruction_array[0];
            if count == 0 {
                print_to_builder(*json, "\"%\": {\n        \"detail\": [\n            \"%\"\n        ],\n", name, instruction.summary);
                append(*json, "        \"description\": [");
            }
            types : [..] string;
            operand_sizes : [10] u64;
            for i: 0 .. instruction.operand_count - 1 {
                width := instruction.operands[i].width;
                if width  operand_sizes[i] |= xx width;
            }
            for i: 0 .. instruction.operand_count - 1 {
                if instruction.operands[i].type == "flags"  continue;
                size_builder : String_Builder;
                init_string_builder(*size_builder);
                s := operand_sizes[i];
                if s {
                    if s & 1  append(*size_builder, "1");
                    if s & 2  append(*size_builder, "2");
                    if s & 4  append(*size_builder, "4");
                    if s & 8  append(*size_builder, "b");
                    if s & 16  append(*size_builder, "w");
                    if s & 32  append(*size_builder, "d");
                    if s & 64  append(*size_builder, "q");
                    if s & 128  append(*size_builder, "x");
                    if s & 256  append(*size_builder, "y");
                    if s & 512  append(*size_builder, "z");
                    if s & 1024  append(*size_builder, "[1024]");
                    if s & 2048  append(*size_builder, "[2048]");
                    if s & 4096  append(*size_builder, "[4096]");

                    array_add(*types, join(instruction.operands[i].type, ".", builder_to_string(*size_builder)));
                }
                else {
                    array_add(*types, instruction.operands[i].type);
                }
            }
            if count  append(*json, ",\n");
            else      append(*json, "\n");
            print_to_builder(*json, "            \"%\"", join(types, ", "));
            count += 1;
        }
        append(*json, "\n        ]\n    }");
    }

    append(*json, "\n}\n");

    write_entire_file(out_file, builder_to_string(*json));

    /*
    displayed_count := 0;
    for variations, instruction_name: instructions {
        if instruction_name == "ADDPS" {
            for instruction_array, hash: variations
                print("%, % (%)\n", instruction_name, to_string(*hash[0]), instruction_array.count);
        }
    }
    */
}



line_number := 0;
//needed_members : Table(string, string);



Instruction :: struct {
    name : string;
    summary : string;
    url_info : string;
    url_ref : string;
    operand_count : int;
    operands : [20] Operand;
}


Valid_Flags :: enum_flags u8 {
    B; W; D; Q;
    X; Y; Z;
}


Operand :: struct {
    idx : int;
    name : string;
    type : string;
    valid : string;
    r : int;
    w : int;
    width : int;
    xtype : string;
    conditionalWrite : bool;
    suppressed : bool;
    implicit : bool;
    base : string;
    seg : string;
    VSIB : string;
    multireg : int;
    opmask : int;
    memory__prefix : string;
    memory__suffix : string;
    flag_AC : string;
    flag_AF : string;
    flag_CF : string;
    flag_DF : string;
    flag_FC0 : string;
    flag_FC1 : string;
    flag_FC2 : string;
    flag_FC3 : string;
    flag_ID : string;
    flag_IF : string;
    flag_IOPL : string;
    flag_NT : string;
    flag_OF : string;
    flag_PF : string;
    flag_RF : string;
    flag_SF : string;
    flag_TF : string;
    flag_VIF : string;
    flag_VIP : string;
    flag_VM : string;
    flag_ZF : string;
}


Hash :: [11] u8;

instruction_hash :: (instruction: Instruction) -> Hash {
    hash : Hash;
    for i: 0 .. instruction.operand_count - 1 {
        if instruction.operands[i].type == {
            case "flags"; hash[i] = #char "f";
            case "imm";   hash[i] = #char "i";
            case "relbr"; hash[i] = #char "b";
            case "reg";   hash[i] = #char "r";
            case "mem";   hash[i] = #char "m";
            case "agen";  hash[i] = #char "a";
        }
    }
    return hash;
}


add_operand :: (using instruction : *Instruction, operand : Operand) {
    operands[operand_count] = operand;
    operand_count += 1;
}


operand_from_string :: (line: string) -> result: Operand {
    operand_label :: "<operand ";
    assert(starts_with(line, operand_label));

    result : Operand;

    tags_and_valid := split(line, ">");

    tag_line := tags_and_valid[0];
    tags_only := ends_with(tag_line, "/");
    if tags_only
        tag_line = slice(tag_line, operand_label.count, -1);
    else
        tag_line = slice(tag_line, operand_label.count);
    parameter, remainder := bite_param(tag_line);
    while parameter {
        defer {
            line_number += 1;
            parameter, remainder = bite_param(remainder);
            //print("[%], [%]\n", parameter, remainder);
        }
        tag, value, ok := param(parameter);
        if !ok {
            print("Param problems on line:\n%\n", line_number);
        }

        #insert -> string {
            info := type_info(Operand);
            builder : String_Builder;
            init_string_builder(*builder);
            append(*builder, "                ");
            for member: info.members {
                string_tag := replace(member.name, "__", "-");
                if member.type.type == {
                    case .STRING;
                    print_to_builder(*builder, "if tag == \"%\"  result.% = value;", string_tag, member.name);

                    case .INTEGER;
                    print_to_builder(*builder, "if tag == \"%\"  result.% = parse_int(*value);", string_tag, member.name);

                    case .BOOL;
                    print_to_builder(*builder, "if tag == \"%\"  result.% = value == \"1\";", string_tag, member.name);
                }
                append(*builder, "\n            else ");
            }
            append(*builder, "assert(false, \"\\n\\nUnknown member: [%] = [%]\", tag, value);");
            //append(*builder, "table_set(*needed_members, tag, value);\n");
            return builder_to_string(*builder);
        }
    }

    if !tags_only {
        valid_string := slice(tags_and_valid[1], 0, -"</operand".count);
        result.valid = valid_string;
        //for reg: split(valid_string, #char ",") {
        //    if contains(.["AH", "BH", "CH", "DH", "SIH", "DIH", "R8B", "])
        //}
    }

    return result;
}



instruction_from_string :: (line: string) -> result: Instruction {
    instruction_label :: "<instruction ";
    assert(starts_with(line, instruction_label));

    result : Instruction;

    tag_line := trim(line);
    tags_only := ends_with(tag_line, "/>");
    if tags_only
        tag_line = slice(tag_line, instruction_label.count, -2);
    else
        tag_line = slice(tag_line, instruction_label.count, -1);
    parameter, remainder := bite_param(tag_line);
    while parameter {
        defer {
            line_number += 1;
            parameter, remainder = bite_param(remainder);
            //print("[%], [%]\n", parameter, remainder);
        }
        tag, value, ok := param(parameter);
        if !ok {
            print("Param problems on line:\n%\n", line_number);
        }
             if tag == "asm"      result.name = value;
        else if tag == "summary"  result.summary = value;
        else if tag == "url"      result.url_info = value;
        else if tag == "url-ref"  result.url_ref = value;
    }

    while result.name.count > 0 && result.name[0] < #char "A" || result.name[0] > #char "Z"
        result.name = slice(result.name, 1);

    return result;
}


param :: (s: string) -> tag: string, value: string, ok: bool {
    parts := split(s, "=");
    assert(parts.count == 2);

    tag := parts[0];
    value := parts[1];
    value = slice(value, 1, -1);
    return tag, value, true;
}


bite_param :: (param_string: string) -> value: string, remainder: string {
    s := trim_start(param_string);
    if s == ""  return "", "";

    i := 0;
    while i < s.count && s[i] != #char "="  i += 1;
    assert(i + 3 < s.count, "Line number: %", line_number);
    assert(s[i + 1] == #char "\"", "Line number: %", line_number);
    i += 2;
    while i < s.count && s[i] != #char "\""  i += 1;
    assert(i < s.count, "Line number: %", line_number);
    i += 1;
    return slice(s, 0, i), slice(s, i);
}


contains :: (haystack: [] string, needle: string) -> bool {
    for haystack  if it == needle  return true;
    return false;
}


print :: (using instruction: Instruction) {
    print("% (%)\n", name, operand_count);
    for i: 0 .. operand_count - 1
        print ("  %: % [%] % = %\n", operands[i].idx, operands[i].name, operands[i].type, operands[i].width, operands[i].valid);
    print("\n\n");
}
