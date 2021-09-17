// Used to run a .jai file in bytecode, without producing an executable.
// Call in long form like this:
//      jai.exe jai_run.jai -- foo.jai [arg [arg...]]
// but it's easier to just use the jai_run.bat file, and do:
//      jai_run foo.jai [arg [arg...]]
//
// To associate .jai files with jai_run you can try to use ftype and assoc like this:
//
// assoc .jai=jaifile
// ftype jaifile="C:\repos\jai-cookbook\tools\run_jai.bat" "%L" %*
//
// ...but this didn't work for me on Windows 10 because Windows 10.  To get it to work I used
// this tool from NirSoft:  http://www.nirsoft.net/utils/filetypesman-x64.zip
// setting the command line for .jai to: (replace with your own path to jai_run.bat)
//
//      "C:\Repos\jai-cookbook\tools\jai_run.bat" "%1" %*
//
// After this I can type "foo.jai bar" on the command line to run foo.jai directly.

// @TODO update to replace `default_metaprogram` instead?


#import "Basic";
#import "Compiler";
#import "String";

set_options :: (using options: *Build_Options) {
    emit_debug_info = .NONE;
    output_path = "c:/temp";
    intermediate_path = "c:/temp";
}


#run {
    args := compiler_get_command_line_arguments();
    if args.count == 0 || !ends_with_nocase(args[0], ".jai") {
        print("Must specify a .jai src file!");
        exit(1);
    }

    filepath := args[0];
    output_path := path_strip_filename(filepath);
    #if OS == .WINDOWS
        executable := join(path_strip_extension(basename(filepath)), ".exe");
    else
        executable := path_strip_extension(basename(filepath));

    set_working_directory(output_path);
    set_build_options_dc(.{do_output = false});

    build_options := get_build_options();
    build_options.output_type = .NO_OUTPUT;
    build_options.output_executable_name = executable;

    workspace := compiler_create_workspace("Main");
    set_build_options(build_options, workspace);
    add_build_file(filepath, workspace);

    builder : String_Builder;
    init_string_builder(*builder);

    if args.count > 0 {
        print_to_builder(*builder, "__new_command_line_strings : [%] string : .[\n", args.count);
        for arg: args  print_to_builder(*builder, "    \"%\",\n", replace(arg, "\\", "\\\\"));
        append(*builder, "];\n");
        print_to_builder(*builder, "__new_command_line_arguments : [%] *u8;\n", args.count);
        append(*builder, "#run {\n");
        for arg, index: args
            print_to_builder(*builder, "    __new_command_line_arguments[%1] = __new_command_line_strings[%1].data;\n", index);
        append(*builder, "    __command_line_arguments.data = __new_command_line_arguments.data;\n");
        append(*builder, "    __command_line_arguments.count = __new_command_line_arguments.count;\n");
        append(*builder, "}\n");
    }

    append(*builder, "#run main();\n");
    add_build_string(builder_to_string(*builder), workspace);
}
