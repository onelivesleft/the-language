#import "Basic";
#import "File";
#import "String";


in_file           :: "jai.yaml";
out_file          :: "../syntaxes/jai.json";
languages_ts_file :: "./languages.ts";


languages :: Language.[
    .{id = "arm",       source = "source.arm",           pattern = "arm"},
    .{id = "cpp",       source = "source.cpp",           pattern = "c(\\+\\+|pp)"},
    .{id = "css",       source = "source.css",           pattern = "css"},
    .{id = "cs",        source = "source.cs",            pattern = "c(sharp|#|s)"},
    .{id = "c",         source = "source.c",             pattern = "c"},
    .{id = "glsl",      source = "source.glsl",          pattern = "glsl"},
    .{id = "hlsl",      source = "source.hlsl",          pattern = "hlsl"},
    .{id = "jai",       source = "source.jai",           pattern = "jai"},
    .{id = "js",        source = "source.js",            pattern = "(js|javascript)"},
    .{id = "java",      source = "source.java",          pattern = "java"},
    .{id = "jsonc",     source = "source.json.comments", pattern = "jsonc"},
    .{id = "json",      source = "source.json",          pattern = "json"},
    .{id = "lua",       source = "source.lua",           pattern = "lua"},
    .{id = "makefile",  source = "source.makefile",      pattern = "make(file)?"},
    .{id = "python",    source = "source.python",        pattern = "py(thon)?"},
    .{id = "shaderlab", source = "source.shaderlab",     pattern = "shaderlab"},
    .{id = "sql",       source = "source.sql",           pattern = "sql"},
    .{id = "toml",      source = "source.toml",          pattern = "toml"},
    .{id = "ts",        source = "source.ts",            pattern = "(ts|typescript)"},
    .{id = "vdf",       source = "source.vdf",           pattern = "(vdf|valve)"},
    .{id = "x64",       source = "source.asm.x86_64",    pattern = "x(86_)?64"},
    .{id = "yaml",      source = "source.yaml",          pattern = "yaml"},
    .{id = "html",      source = "text.html.derivative", pattern = "x?html"},
    .{id = "md",        source = "text.html.markdown",   pattern = "(md|markdown)"},
    .{id = "xml",       source = "text.xml",             pattern = "xml"},
    .{id = "xsl",       source = "text.xml.xsl",         pattern = "xsl"},
];

Language :: struct {
    id      : string;
    source  : string;
    pattern : string;
}


json : String_Builder;
out :: #bake_arguments print_to_builder(builder = *json);

tab :: (depth: int) #expand {
    for 0..depth  out("    ");
}


stack : [..] Node_Type;
stack_index := -1;

Node_Type :: enum {
    LIST;
    DICT;
    UNKNOWN;
}

push_stack :: (node_type: Node_Type) {
    stack_index += 1;
    if stack_index >= stack.count
        array_add(*stack, node_type);
    else
        stack[stack_index] = node_type;

}

pop_stack :: () {
    stack_index -= 1;
}

peek_stack :: () -> Node_Type {
    return stack[stack_index];
}

line_number := 0;


main :: () {
    yaml_file_data, success := read_entire_file(in_file);
    if !success {
        print("Failed to read %", in_file);
        exit(1);
    }

    languages_ts : String_Builder;
    init_string_builder(*languages_ts);
    append(*languages_ts, "export const languages = [\n");
    for language: languages
        print_to_builder(*languages_ts, "    [\"%\", /.*%/i],\n", language.id, language.pattern);
    append(*languages_ts, "];\n");
    write_entire_file(languages_ts_file, builder_to_string(*languages_ts));

    yaml : String_Builder;
    init_string_builder(*yaml);
    append(*yaml, replace(yaml_file_data, "\r", ""));

    append(*yaml, markdown_block_comments_header);
    for language: languages
        print_to_builder(*yaml, markdown_block_comments_language, language.pattern, language.id, language.source);
    append(*yaml, markdown_block_comments_footer);

    append(*yaml, strings_header);
    for language: languages
        print_to_builder(*yaml, strings_language, language.pattern, language.id, language.source);
    append(*yaml, strings_footer);

    init_string_builder(*json);

    depth := 0;
    previous_depth := -1;
    close_list_dict := false;
    push_stack(.DICT);
    out("{");

    yaml_string := builder_to_string(*yaml);

    for row, index: split(yaml_string, "\n") {
        line_number = index + 1;
        spaces := 0;
        while spaces < row.count && row[spaces] == #char " "
            spaces += 1;
        if spaces >= row.count  continue;
        if spaces % 2 {
            print("Irregular tab indent on line %\n", line_number);
            exit(1);
        }
        depth = spaces / 2;

        key, value, is_list_entry := parse_row(row);

        if peek_stack() == .UNKNOWN {
            if depth <= previous_depth {
                print("Expected indent on line %\n", line_number);
                exit(1);
            }

            tab(previous_depth);

            if is_list_entry {
                stack[stack_index] = .LIST;
                out("[\n");
            }
            else {
                stack[stack_index] = .DICT;
                out("{\n");
            }
        }
        else if previous_depth == depth {
            if is_list_entry && peek_stack() == .LIST {
                out(" },\n");
            }
            else
                out(",\n");
        }
        else if depth > previous_depth && previous_depth >= 0 {
            if peek_stack() != .LIST {
                print("Error on line %\n", line_number);
                exit(1);
            }
            out(",\n");
            push_stack(.DICT);
        }
        else {
            while previous_depth > depth {
                out("\n");
                tab(previous_depth - 1);
                if stack[previous_depth] == .LIST {
                    if close_list_dict {
                        out(" }");
                        close_list_dict = false;
                    }
                    out("]");
                }
                else
                    out("}");
                previous_depth -= 1;
                pop_stack();
            }
            if previous_depth == depth
                out(",\n");
            else
                out("\n");
        }

        tab(depth);

        close_list_dict = false;
        if value == "" {
            push_stack(.UNKNOWN);
            out("\"%\":\n", key);
        }
        else {
            if peek_stack() == .LIST {
                out("{ ");
                close_list_dict = true;
            }
            out("\"%\": \"%\"", key, value);
        }

        previous_depth = depth;
    }

    while previous_depth > 0 {
        out("\n");
        tab(previous_depth - 1);
        if stack[previous_depth] == .LIST {
            if close_list_dict {
                out(" }");
                close_list_dict = false;
            }
            out("]");
        }
        else
            out("}");
        previous_depth -= 1;
        pop_stack();
    }
    out("\n}");

    write_entire_file(out_file, builder_to_string(*json));
}


parse_row :: (row_data: string) -> key: string, value: string, is_list_entry: bool {
    row := replace(trim_left(row_data), "\\", "\\\\");

    is_list_entry := false;
    if starts_with(row, "- ") {
        is_list_entry = true;
        row.data += 2;
        row.count -= 2;
    }

    colon := index_of_char(row, #char ":");
    if colon == -1 {
        print("Missing ':' on line %\n", line_number);
        exit(1);
    }

    key := slice(row, 0, colon);
    value := slice(row, colon + 1, row.count - (colon + 1));
    value = trim(value);

    key = fix_up(key);
    value = fix_up(value);

    return key, value, is_list_entry;


    fix_up :: (s: string) -> string {
        return replace(trim(s, "'"), "\"", "\\\"");
    }
}


// @Note bare-bones YAML parsing, so 2-space indents only!

markdown_block_comments_header :: #string ___yaml
  markdown-block-comments:
    name: meta.embedded.block.markdown
    begin: (\/\*\*)
    end: (\*\/)
    beginCaptures:
      '1':
        name: punctuation.definition.comment.jai
    endCaptures:
      '1':
        name: punctuation.definition.comment.jai
    patterns:
      - include: '#block-comments'
___yaml

markdown_block_comments_language :: #string yaml
      - begin: ((?i)```%1)
        end: (```)
        beginCaptures:
          '1':
            name: markup.quote.code.comment.%2.jai
        endCaptures:
          '1':
            name: markup.quote.code.comment.%2.jai
        patterns:
          - include: %3
yaml

markdown_block_comments_footer :: #string yaml
      - begin: (```)
        end: (```)
        beginCaptures:
          '1':
            name: markup.quote.code.comment.jai
        endCaptures:
          '1':
            name: markup.quote.code.comment.jai
        patterns:
          - include: source.jai
      - contentName: meta.embedded.block.markdown
        include: text.html.markdown
yaml


strings_header :: #string ___yaml
  strings:
    patterns:
      - name: string.quoted.double.empty.jai
        match: (")(")
        captures:
          '1':
            name: punctuation.definition.string.empty.begin.jai
          '2':
            name: punctuation.definition.string.empty.end.jai
      - name: string.quoted.double.jai
        begin: (")
        end: ("|$)
        beginCaptures:
          '1':
            name: punctuation.definition.string.begin.jai
        endCaptures:
          '1':
            name: punctuation.definition.string.end.jai
        patterns:
          - name: constant.character.escape.jai
            match: \\.
___yaml

strings_language :: #string ___yaml
      - name: string.here.embed.%2.jai
        begin: '(#string)\s+((?i)([A-Za-z_]\w*)?(%1))\b'
        end: \s*(\3)(\4)
        beginCaptures:
          '1':
            name: keyword.other.directive.string.%2.jai
          '2':
            name: constant.other.stringdelimiter.here.embed.%2.jai
          '4':
            name: constant.other.stringdelimiter.here.embed.language.%2.jai
        endCaptures:
          '1':
            name: constant.other.stringdelimiter.here.embed.%2.jai
          '2':
            name: constant.other.stringdelimiter.here.embed.language.%2.jai
        contentName: string.unquoted.here.embed.%2.jai
        patterns:
          - include: %3
___yaml

strings_footer :: #string ___yaml
      - name: string.here.jai
        begin: '(#string)\s+([A-Za-z_]\w*)'
        end: \s*(\2)
        beginCaptures:
          '1':
            name: keyword.other.directive.string.jai
          '2':
            name: constant.other.stringdelimiter.here.jai
        endCaptures:
          '1':
            name: constant.other.stringdelimiter.here.jai
        contentName: string.unquoted.here.jai
___yaml
