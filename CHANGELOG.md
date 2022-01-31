# Change Log

## [0.0.85] - 2022-01-31
* Fixed errors not clearing when fixed.

## [0.0.84] - 2022-01-16
* Added backslash spacing of names (`last\ time : float64`)

## [0.0.83] - 2022-01-15
* Updated for v0.1.003

## [0.0.82] - 2021-12-01
* Updated for v97

## [0.0.81] - 2021-11-27
* Updated jai_run to not leave as many files lying around.
* Added `__temporary_allocator` to deprecated

## [0.0.80] - 2021-11-02
* Added `Run Snippet Header` setting.
* Added `inline` keyword.

## [0.0.79] - 2021-10-12
* Added `Jai: Run Snippet` command: allows you to run jai code selected in any document.  If no code selected then will check for surrounding ```.

## [0.0.78] - 2021-10-06
* Restored VSCodeLocate not emitting debug output (was workaround for compiler bug).
* Added option to disable background compilation (and therefor IDE-like features).
* Added missing support functions from `Basic`.

## [0.0.77] - 2021-10-04
* Errors & Warnings are now reported to Problems panel.
* `jai.exe` call is now logged in full as a string when `Debug Mode` is enabled, for easy copypasting.
* Fixed missing deprecated procedures.
* Added FoldingRange provider.

## [0.0.76] - 2021-09-29
* Added `#bake_constants`.

## [0.0.75] - 2021-09-29
* Added `#this`.

## [0.0.74] - 2021-09-29
* Actually added `#type,isa`, `#type,distinct`.

## [0.0.73] - 2021-09-29
* Added `#type,isa`, `#type,distinct`.
* Fixed asm goto-definition help not working until after lazy-load of asm definitions.

## [0.0.72] - 2021-09-20
* Made reference-find smarter when file is currently ill-formed.

## [0.0.71] - 2021-09-19
* Lazily load asm completions once user is in an asm block.
* Added #asm feature-set syntax
* Fixed #expand after return type(s)

## [0.0.70] - 2021-09-18
* Fixed previous version breaking syntax highlighting.

## [0.0.69] - 2021-09-18
* Autogenerate deprecated info from jai modules folder.
* Autogenerate support.function and support.class info from jai modules folder.
* Added `remove` keyword.

## [0.0.68] - 2021-09-17
* Added `projectJaiArgs` setting to allow you to pass additional args to the compiler, such as an extra `-import_dir`.
* Fixed reference update erroneously triggering for all files, instead of just `.jai` files.
* Fixed compiler calls on uncompilable files locking the feature

## [0.0.67] - 2021-09-16
* Whenever you save a file the compiler will be called to try and compile newer reference data.
* Reference and Definition providers now run off this cached data.

## [0.0.66] - 2021-09-14
* Fixed bugs when running under linux

## [0.0.65] - 2021-08-27
* Fully fleshed out #asm instruction info.
* If you hit goto definition (F12) on an instruction it will open the relevant felixcloutier.com page.

## [0.0.64] - 2021-08-27
* Fix misnamed json file.

## [0.0.63] - 2021-08-26
* Added completion suggestions in `#asm` blocks.

## [0.0.62] - 2021-08-17
* Fixed `#asm`.

## [0.0.61] - 2021-08-17
* Updated `asm` to `#asm`.
* Goto definition works inside `.added_strings_#.jai` files (it will take you to the code which created the string).

## [0.0.60] - 2021-08-15
* Added `asm` keyword and block syntax highlighting.

## [0.0.59] - 2021-08-12
* Fixed doc comments (`/**`) not allowing prefix whitespace.
* A string like `"foo #string something"` will no longer create a decorator block.
* Fixed anonymous enums/structs not highlighting correctly.
* Added `#no_context` and cleaned up some removed / deprecated calls.
* Made `context` a keyword.
* Fixed `#type` declarations.
* Fixed comma-separated declarations/assignments.

## [0.0.58] - 2021-08-08
* Locate now works on projects, not just single files.
* Locate now reports idents in any file, including library files.

## [0.0.57] - 2021-08-07
* Test adding files to `out`
* `Debug Mode` setting

## [0.0.56] - 2021-08-07
* Removed `#run_and_insert`
* Basic LSP functions: can goto definition, find references, rename (but only in single files, and is probably buggy).

## [0.0.55] - 2021-05-01
* Fix MD codeblock

## [0.0.54] - 2021-03-28
* `#no_reset`
* MD codeblock support

## [0.0.53] - 2021-03-19
* `#code` outwith parameters

## [0.0.52] - 2021-03-19
* `#unshared` + `#procedure_of_call`
* fixed checklists
* fixed `for` loops
* fixed `*/` ending decorator blocks

## [0.0.51] - 2021-03-09
* Fix order

## [0.0.50] - 2021-03-09
* Added shader pseudonym for glsl

## [0.0.49] - 2021-03-07
* Added `Decorate Embedded Blocks` option.

## [0.0.48] - 2021-03-07
* Added `#foreign "..."`
* Added `log_error`
* Fixed `if()`
* Fixed `cast`

## [0.0.47] - 2021-03-04
* Fixed it/it_index declarations

## [0.0.46] - 2021-03-03
* Fixed string parameters
* Added % formatting characters

## [0.0.45] - 2021-03-02
* Added annotation parameters

## [0.0.44] - 2021-03-01
* Namespace struct sub-members

## [0.0.43] - 2021-03-01
* Updated README

## [0.0.42] - 2021-03-01
* fixed checklist grammar
* Updated README

## [0.0.41] - 2021-02-28
* factored languages
* added a couple more languages

## [0.0.40] - 2021-02-28
* fixed selection interaction with decorations

## [0.0.39] - 2021-02-27
* checklist comments

## [0.0.38] - 2021-02-27
* remove vestigial decorations

## [0.0.37] - 2021-02-27
* better config defaults

## [0.0.36] - 2021-02-27
* embed language background color decorations

## [0.0.35] - 2021-02-26
* rewrite into yaml + build script
* lots more languages
* `#string` wrappers

## [0.0.34] - 2021-02-25
* `main`

## [0.0.33] - 2021-02-21
* cast parameters

## [0.0.32] - 2021-02-21
* `using` parameter

## [0.0.31] - 2021-02-21
* Added `log`

## [0.0.30] - 2021-02-19
* Fix support.function calls

## [0.0.29] - 2021-02-08
* Fix arrays

## [0.0.28] - 2021-02-08
* Fix comments at end of line

## [0.0.27] - 2021-02-08
* Fix string not understanding escaped "

## [0.0.26] - 2021-02-07
* Fix here string not ignoring whitespace

## [0.0.25] - 2021-02-07
* Fix incorrect ) match in parameters

## [0.0.24] - 2021-02-07
* Added @tags in comments
* Added @Note signature in comments

## [0.0.23] - 2021-02-06
* Added support for doc-comments (`/**`)
* Added highlight to things quoted with backticks in comments

## [0.0.22] - 2021-02-03
* Fixed non-namespaced proc call

## [0.0.21] - 2021-02-03
* Fixed #import/#load when not at start of line

## [0.0.20] - 2021-02-01
* Fixed enum member as parameter
* Fixed namespace.proc() call

## [0.0.19] - 2021-01-28
* Fixed cast()
* composite literals

## [0.0.18] - 2021-01-28
* deprecations

## [0.0.17] - 2021-01-27
* all directives
* @tag in function return

## [0.0.16] - 2021-01-27
* better #load/#import

## [0.0.15] - 2021-01-27
* #placeholder

## [0.0.14] - 2021-01-26
* fixed enum member

## [0.0.13] - 2021-01-26
* fixed enum

## [0.0.12] - 2021-01-26
* for_expansion
* ~.ENUM

## [0.0.11] - 2021-01-25
* #must

## [0.0.10] - 2021-01-25
* typo

## [0.0.9] - 2021-01-25
* no_inline, Type
* true, false, null
* enum_flags

## [0.0.8] - 2021-01-25
* better parameter grammar

* ## [0.0.7] - 2021-01-25
* better for grammar

## [0.0.6] - 2021-01-25
* xx is a cast
* better cast grammar
* grammar fixes

## [0.0.5] - 2021-01-25
* Basic provider functionality
* Here strings, nested comments

## [0.0.4] - 2021-01-24
* Mostly mostly grammared

## [0.0.3] - 2021-01-24
* Mostly grammared

## [0.0.2] - 2021-01-23
* First release.
