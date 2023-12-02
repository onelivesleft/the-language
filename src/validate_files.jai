#import "Basic";
#import "File";
#import "String";


package_file      :: "../package.json";
changelog_file    :: "../CHANGELOG.md";


main :: () {
    trim_start :: (s: string, delimiter: $T) -> trimmed: string, found: bool {
      trim_count := find_index_from_left(s, delimiter);

      trimmed := "";
      found := trim_count != -1;
      if found {
          trimmed = slice(s, trim_count, s.count - trim_count);
      }

      return trimmed, found;
    }

    trim_start_past :: (s: string, delimiter: $T) -> trimmed: string, found: bool {
      trim_count := find_index_from_left(s, delimiter) + 1;

      trimmed := "";
      found := trim_count != -1;
      if found {
          trimmed = slice(s, trim_count, s.count - trim_count);
      }

      return trimmed, found;
    }

    trim_through :: (s: string, delimiter: $T) -> trimmed: string {
      left := find_index_from_left(s, delimiter) + 1;
      trimmed := slice(s, left, s.count - left);
      right := find_index_from_left(trimmed, delimiter);
      trimmed.count = right;
      return trimmed;
    }

    advance_past :: (s: *string, delimiter: u8) {
      << s = trim_start_past(<< s, delimiter);
    }

    changelog_report := trim_start_past(changelog_file, cast(u8) #char "/");
    package_report := trim_start_past(package_file, cast(u8) #char "/");

    package, package_ok := read_entire_file(package_file);
    if !package_ok {
        print("Unable to open %\n", package_report);
        exit(7);
    }

    package_version : string;
    for line: split(package, "\n") {
        text, found := trim_start_past(line, "\"version\"");
        if found {
            package_version = trim_through(text, cast(u8) #char "\"");
            break;
        }
    }

    if !package_version {
        print("Couldn't find \"version\" label in %\n", package_report);
        exit(8);
    }

    changelog, changelog_ok := read_entire_file(changelog_file);
    if !changelog_ok {
        print("Unable to open %\n", changelog_report);
        exit(9);
    }

    changelog_version : string;
    changelog_date : string;
    for line: split(changelog, "\n") {
        text := trim_left(line);
        // ## [0.0.77] - 2021-10-
        if starts_with(text, "## ") {
            advance_past(*text, #char "[");
            changelog_ok, changelog_version, changelog_date = split_from_left(text, #char "]");
            changelog_date = trim_start_past(changelog_date, " - ");
            break;
        }
    }

    if !changelog_version {
        print("Couldn't find version in %\n", changelog_report);
        exit(10);
    }

    if package_version != changelog_version {
        print("Version mismatch:\n");
        print("% version: %\n", changelog_report, changelog_version);
        print("% version: %\n", package_report, package_version);
        exit(11);
    }

    date_valid := changelog_date.count == 10 ;
    if date_valid {
        for i: 0 .. 9 {
            if i == 4 || i == 6 {
                if changelog_date[i] != #char "-" {
                    date_valid := false;
                    break;
                }
            }
            else {
                if !is_digit(changelog_date[i]) {
                    date_valid := false;
                    break;
                }
            }
        }
    }

    if !date_valid {
        print("Invalid date in %:\n%\n", changelog_report, changelog_date);
        exit(12);
    }
}
