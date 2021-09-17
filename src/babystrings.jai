#import "Basic";
#import "Machine_X64";


default_compare :: case_sensitive;


Character_Compare :: struct {
    kind : enum { CASE_SENSITIVE; IGNORE_CASE; CUSTOM; };
    compare : #type(a: u8, b: u8) -> bool;
}

Index_Proc :: #type(haystack: string, needle: string, boundary_index: int, reverse: bool) -> from_index: int, to_index: int, found: bool;


#scope_file

String_Index_Proc :: #type(haystack: string, needle: string, start_index: int, compare: Character_Compare) -> index: int, found: bool;

simd_mode : enum { OFF; AUTO; SSE; AVX2; } = .SSE;

#scope_export


set_simd_mode :: (mode: type_of(simd_mode)) {
    if mode == .AUTO {
        if get_cpu_info().AVX2
            simd_mode = .AVX2;
        else
            simd_mode = .SSE;
    }
    else
        simd_mode = mode;
}


is_any :: inline (needle: u8, characters: [] u8, compare : Character_Compare) -> bool {
    for character: characters
        if compare.compare(needle, character)  return true;

    return false;
}


case_sensitive :: Character_Compare.{
    .CASE_SENSITIVE,
    (a: u8, b: u8) -> bool {
        return a == b;
    }
};


ignore_case :: Character_Compare.{
    .IGNORE_CASE,
    (a: u8, b: u8) -> bool {
        return (ifx a >= #char "A" && a <= #char "Z" then a | 32 else a)
            == (ifx b >= #char "A" && b <= #char "Z" then b | 32 else b);
    }
};

// ignore_case in asm, but it's slower...
/*
ptr_a := *a;
ptr_b := *b;
result : u8 = 0; // true
ptr_result := *result;
#asm {
    a : gpr;
    b : gpr;
    low : gpr;
    high : gpr;
    mov.b   a, [ptr_a];
    mov.b   b, [ptr_b];
    or.b    a, 32;
    or.b    b, 32;
    xor.b   a, b;
    cmp.b   b, 97;  // a
    setl    low;
    cmp.b   b, 122; // z
    setg    high;
    or.b    a, low;
    or.b    a, high;
    mov.b   [ptr_result], a;
}
return result == 0;
*/


string_from_char :: inline (char: *u8) -> string {
    result : string = ---;
    result.data = char;
    result.count = 1;
    return result;
}


unsafe_slice :: inline (str: string, from_index: int, to_index: int) -> string {
    // @Note Handles positive indexes only!
    assert(from_index >= 0 && from_index <= str.count, "Cannot slice; from_index falls outwith range of string.");
    assert(to_index >= from_index, "Cannot slice; to_index is ahead of from_index.");
    assert(to_index <= str.count, "Cannot slice; to_index falls outwith range of string.");

    result : string = ---;
    result.data = str.data + from_index;
    result.count = to_index - from_index;
    return result;
}


unsafe_slice :: inline (str: string, from_index: int) -> string {
    // @Note Handles positive index only!
    assert(from_index >= 0 && from_index <= str.count, "Cannot slice; from_index falls outwith range of string.");

    result : string = ---;
    result.data = str.data + from_index;
    result.count = str.count - from_index;
    return result;
}


validate_start_index :: (str: string) #expand {
    if `start_index < 0  `start_index = clamp(str.count + `start_index, 0, str.count);
    else                 `start_index = clamp(`start_index, 0, str.count);
}


#scope_file

make_16 :: (value: u8) -> string {
    return sprint("u8.[%1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1];", value);
}

make_32 :: (value: u8) -> string {
    return sprint("u8.[%1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1];", value);
}

make_64 :: (value: u8) -> string {
    return sprint("u8.[%1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1, %1];", value);
}

#scope_export


first_index :: (haystack: string, needle: u8, start_index: int, compare: Character_Compare) -> index: int, found: bool {
    validate_start_index(haystack);

    handled := false;

    if compare.kind == {
        case .CASE_SENSITIVE;
            data := cast(u64)haystack.data + cast(u64)start_index;
            end := cast(u64)haystack.data + cast(u64)haystack.count;

            if simd_mode == {
                case .SSE;
                    handled = true;

                    needles : [16] u8 = ---;
                    memset(needles.data, needle, 16);
                    needle_data := needles.data;

                    // @TODO Update to use two asm blocks - setup + loop - when compiler supports it

                    results : struct { index, found : u16; };
                    results_data := *results;

                    loop_until := end - 15;

                    while data < loop_until {
                        #asm {
                            needle_vec: vec;
                            haystack_vec: vec;
                            results_vec: vec;
                            found_gpr: gpr;
                            index_gpr: gpr;

                            movdqu.x needle_vec, [needle_data];
                            movdqu.x haystack_vec, [data];
                            pcmpeqb.x results_vec, haystack_vec, needle_vec;
                            pmovmskb.x found_gpr, results_vec;
                            tzcnt.w index_gpr, found_gpr;
                            shl.d found_gpr, 16;
                            or.w found_gpr, index_gpr;
                            mov.d [results_data], found_gpr;
                        }

                        if results.found
                            return cast(int)(data - cast(u64)haystack.data + results.index), true;
                        else
                            data += 16;
                    }

                    for data .. min(data + 15, end - 1)
                        if compare.compare(<<cast(*u8)it, needle)
                            return cast(int)(it - cast(u64)haystack.data), true;

                case .AVX2;
                    handled = true;

                    needles : [32] u8 = ---;
                    memset(needles.data, needle, 32);
                    needle_data := needles.data;

                    results : struct { index, found : u32; };
                    results_data := *results;

                    loop_until := end - 31;

                    while data < loop_until {
                        #asm {
                            needle_vec: vec;
                            haystack_vec: vec;
                            results_vec: vec;
                            found_gpr: gpr;
                            index_gpr: gpr;

                            movdqu.y needle_vec, [needle_data];
                            movdqu.y haystack_vec, [data];
                            pcmpeqb.y results_vec, haystack_vec, needle_vec;
                            pmovmskb.y found_gpr, results_vec;
                            xor.q index_gpr, index_gpr;
                            tzcnt.d index_gpr, found_gpr;
                            shl.q found_gpr, 32;
                            or.q found_gpr, index_gpr;
                            mov.q [results_data], found_gpr;
                        }

                        if results.found
                            return cast(int)(data - cast(u64)haystack.data + results.index), true;
                        else
                            data += 32;
                    }

                    for data .. min(data + 31, end - 1)
                        if compare.compare(<<cast(*u8)it, needle)
                            return cast(int)(it - cast(u64)haystack.data), true;
            }

        case .IGNORE_CASE;
            data := cast(u64)haystack.data + cast(u64)start_index;
            end := cast(u64)haystack.data + cast(u64)haystack.count;

            if simd_mode == {
                case .SSE;
                    handled = true;
                    needles : [16] u8 = ---;
                    memset(needles.data, needle, 16);
                    needle_data := needles.data;

                    case_bit :: 32;
                    case_bytes := #insert #run make_16(case_bit);
                    a_bytes    := #insert #run make_16(#char "a");
                    z_bytes    := #insert #run make_16(#char "z");

                    case_data := *case_bytes;
                    a_data := *a_bytes;
                    z_data := *z_bytes;

                    results : struct { index, found : u16; };
                    results_data := *results;

                    loop_until := end - 15;

                    while data < loop_until {
                        #asm {
                            needle_vec: vec;
                            haystack_vec: vec;
                            case_vec: vec;
                            a_vec: vec;
                            z_vec: vec;
                            result_cased_vec: vec;
                            result_nocase_vec: vec;
                            bounds_vec: vec;
                            mask_vec: vec;
                            found_gpr: gpr;
                            index_gpr: gpr;

                            movdqu.x case_vec, [case_data];
                            movdqu.x a_vec, [a_data];
                            movdqu.x z_vec, [z_data];

                            movdqu.x needle_vec, [needle_data];
                            movdqu.x haystack_vec, [data];
                            pcmpeqb.x result_cased_vec, needle_vec, haystack_vec;

                            por.x haystack_vec, case_vec;
                            por.x needle_vec, case_vec;
                            pcmpeqb.x result_nocase_vec, needle_vec, haystack_vec;

                            movdqa.x mask_vec, haystack_vec;
                            pcmpgtb.x mask_vec, z_vec;

                            movdqa.x bounds_vec, a_vec;
                            pcmpgtb.x bounds_vec, haystack_vec;
                            por.x mask_vec, bounds_vec;
                            pand.x result_cased_vec, mask_vec;

                            pcmpeqb.x bounds_vec, bounds_vec, bounds_vec;
                            pxor.x mask_vec, bounds_vec;

                            pand.x result_nocase_vec, mask_vec;
                            por.x result_cased_vec, result_nocase_vec;

                            pmovmskb.x found_gpr, result_cased_vec;
                            tzcnt.w index_gpr, found_gpr;
                            shl.d found_gpr, 16;
                            or.w found_gpr, index_gpr;
                            mov.d [results_data], found_gpr;
                        }

                        if results.found
                            return cast(int)(data - cast(u64)haystack.data + results.index), true;
                        else
                            data += 16;
                    }

                    for data .. min(data + 15, end - 1)
                        if compare.compare(<<cast(*u8)it, needle)
                            return cast(int)(it - cast(u64)haystack.data), true;

                case .AVX2;
                    handled = true;

                    needles : [32] u8 = ---;
                    memset(needles.data, needle, 32);
                    needle_data := needles.data;

                    case_bit :: 32;
                    case_bytes := #insert #run make_32(case_bit);
                    a_bytes    := #insert #run make_32(#char "a");
                    z_bytes    := #insert #run make_32(#char "z");

                    case_data := *case_bytes;
                    a_data := *a_bytes;
                    z_data := *z_bytes;

                    results : struct { index, found : u32; };
                    results_data := *results;

                    loop_until := end - 31;

                    while data < loop_until {
                        #asm {
                            needle_vec: vec;
                            haystack_vec: vec;
                            case_vec: vec;
                            a_vec: vec;
                            z_vec: vec;
                            result_cased_vec: vec;
                            result_nocase_vec: vec;
                            bounds_vec: vec;
                            mask_vec: vec;
                            found_gpr: gpr;
                            index_gpr: gpr;

                            movdqu.y case_vec, [case_data];
                            movdqu.y a_vec, [a_data];
                            movdqu.y z_vec, [z_data];

                            movdqu.y needle_vec, [needle_data];
                            movdqu.y haystack_vec, [data];
                            pcmpeqb.y result_cased_vec, needle_vec, haystack_vec;


                            por.y haystack_vec, haystack_vec, case_vec;
                            por.y needle_vec, needle_vec, case_vec;
                            pcmpeqb.y result_nocase_vec, needle_vec, haystack_vec;

                            pcmpgtb.y mask_vec, haystack_vec, z_vec;

                            pcmpgtb.y bounds_vec, a_vec, haystack_vec;
                            por.y mask_vec, mask_vec, bounds_vec;
                            pand.y result_cased_vec, result_cased_vec, mask_vec;

                            pcmpeqb.y bounds_vec, bounds_vec, bounds_vec;
                            pxor.y mask_vec, mask_vec, bounds_vec;

                            pand.y result_nocase_vec, result_nocase_vec, mask_vec;
                            por.y result_cased_vec, result_cased_vec, result_nocase_vec;

                            pmovmskb.y found_gpr, result_cased_vec;
                            xor.q index_gpr, index_gpr;
                            tzcnt.d index_gpr, found_gpr;
                            shl.q found_gpr, 32;
                            or.q found_gpr, index_gpr;
                            mov.q [results_data], found_gpr;
                        }

                        if results.found
                            return cast(int)(data - cast(u64)haystack.data + results.index), true;
                        else
                            data += 32;
                    }

                    for data .. min(data + 31, end - 1)
                        if compare.compare(<<cast(*u8)it, needle)
                            return cast(int)(it - cast(u64)haystack.data), true;
            }
    }

    if !handled {
        for cast(u64)haystack.data + cast(u64)start_index .. cast(u64)haystack.data + cast(u64)haystack.count - 1
            if compare.compare(<<cast(*u8)it, needle)
                return cast(int)(it - cast(u64)haystack.data), true;
    }

    return -1, false;
}


first_index :: inline (haystack: string, needle: u8, compare: Character_Compare) -> index: int, found: bool {
    index, found := first_index(haystack, needle, 0, compare);
    return index, found;
}


first_index :: (haystack: string, needle: [] u8, start_index := 0, compare: Character_Compare) -> index: int, found: bool {
    validate_start_index(haystack);

    for cast(u64)haystack.data + cast(u64)start_index .. cast(u64)haystack.data + cast(u64)haystack.count - 1
        if is_any(<<cast(*u8)it, needle, compare)
            return cast(int)(it - cast(u64)haystack.data), true;

    return -1, false;
}


first_index :: inline (haystack: string, needle: string, start_index: int, string_index_proc: String_Index_Proc, compare : Character_Compare) -> index: int, found: bool {
    validate_start_index(haystack);
    if needle.count == 0 {
        return start_index, true;
    }
    else if needle.count == 1 {
        index, found := first_index(haystack, << needle.data, start_index, compare);
        return index, found;
    }
    else {
        index, found := string_index_proc(haystack, needle, start_index, compare);
        return index, found;
    }
}


first_index :: inline (haystack: string, needle: string, string_index_proc: String_Index_Proc, compare: Character_Compare) -> index: int, found: bool {
    index, found := first_index(haystack, needle, 0, string_index_proc, compare);
    return index, found;
}


first_index :: inline (haystack: string, needle: string, start_index := 0, $$index: Index_Proc) -> from_index: int, found: bool, to_index: int {
    from_index, to_index, found := index(haystack, needle, start_index, false);
    return from_index, found, to_index;
}



last_index :: inline (haystack: string, needle: u8, compare: Character_Compare) -> index: int, found: bool {
    index, found := last_index(haystack, needle, haystack.count, compare);
    return index, found;
}


last_index :: (haystack: string, needle: u8, start_index: int, compare: Character_Compare) -> index: int, found: bool {
    if start_index == 0  return -1, false;

    start_index -= 1;
    validate_start_index(haystack);

    handled := false;

    if compare.kind == {
        case .CASE_SENSITIVE;
            if simd_mode == {
                case .SSE;
                    if start_index >= 15 {
                        handled = true;

                        data := cast(u64)haystack.data + cast(u64)start_index - 15;
                        end := cast(u64)haystack.data;

                        needles : [16] u8 = ---;
                        memset(needles.data, needle, 16);
                        needle_data := needles.data;

                        results : struct { index, found : u16; };
                        results_data := *results;

                        while data >= end {
                            #asm {
                                needle_vec: vec;
                                haystack_vec: vec;
                                results_vec: vec;
                                found_gpr: gpr;
                                index_gpr: gpr;

                                movdqu.x needle_vec, [needle_data];
                                movdqu.x haystack_vec, [data];
                                pcmpeqb.x results_vec, haystack_vec, needle_vec;
                                pmovmskb.x found_gpr, results_vec;
                                lzcnt.w index_gpr, found_gpr;
                                shl.d found_gpr, 16;
                                or.w found_gpr, index_gpr;
                                mov.d [results_data], found_gpr;
                            }

                            if results.found
                                return cast(int)(data - cast(u64)haystack.data + 15 - results.index), true;
                            else
                                data -= 16;
                        }

                        for < data + 15 .. max(data, end)
                            if compare.compare(<<cast(*u8)it, needle)
                                return cast(int)(it - cast(u64)haystack.data), true;
                    }

                case .AVX2;
                    if start_index >= 31 {
                        handled = true;

                        data := cast(u64)haystack.data + cast(u64)start_index - 31;
                        end := cast(u64)haystack.data;

                        needles : [32] u8 = ---;
                        memset(needles.data, needle, 32);
                        needle_data := needles.data;

                        results : struct { index, found : u32; };
                        results_data := *results;

                        while data >= end {
                            #asm {
                                needle_vec: vec;
                                haystack_vec: vec;
                                results_vec: vec;
                                found_gpr: gpr;
                                index_gpr: gpr;

                                movdqu.y needle_vec, [needle_data];
                                movdqu.y haystack_vec, [data];
                                pcmpeqb.y results_vec, haystack_vec, needle_vec;
                                pmovmskb.y found_gpr, results_vec;
                                xor.q index_gpr, index_gpr;
                                lzcnt.d index_gpr, found_gpr;
                                shl.q found_gpr, 32;
                                or.q found_gpr, index_gpr;
                                mov.q [results_data], found_gpr;
                            }

                            if results.found
                                return cast(int)(data - cast(u64)haystack.data + 31 - results.index), true;
                            else
                                data -= 32;
                        }

                        for < data + 32 .. max(data, end)
                            if compare.compare(<<cast(*u8)it, needle)
                                return cast(int)(it - cast(u64)haystack.data), true;
                    }
            }

        case .IGNORE_CASE;
            if simd_mode == {
                case .SSE;
                    if start_index >= 15 {
                        handled = true;

                        data := cast(u64)haystack.data + cast(u64)start_index - 15;
                        end := cast(u64)haystack.data;

                        needles : [16] u8 = ---;
                        memset(needles.data, needle, 16);
                        needle_data := needles.data;

                        case_bit :: 32;
                        case_bytes := #insert #run make_16(case_bit);
                        a_bytes    := #insert #run make_16(#char "a");
                        z_bytes    := #insert #run make_16(#char "z");

                        case_data := *case_bytes;
                        a_data := *a_bytes;
                        z_data := *z_bytes;

                        results : struct { index, found : u16; };
                        results_data := *results;

                        while data >= end {
                            #asm {
                                needle_vec: vec;
                                haystack_vec: vec;
                                case_vec: vec;
                                a_vec: vec;
                                z_vec: vec;
                                result_cased_vec: vec;
                                result_nocase_vec: vec;
                                bounds_vec: vec;
                                mask_vec: vec;
                                found_gpr: gpr;
                                index_gpr: gpr;

                                movdqu.x case_vec, [case_data];
                                movdqu.x a_vec, [a_data];
                                movdqu.x z_vec, [z_data];

                                movdqu.x needle_vec, [needle_data];
                                movdqu.x haystack_vec, [data];
                                pcmpeqb.x result_cased_vec, needle_vec, haystack_vec;

                                por.x haystack_vec, case_vec;
                                por.x needle_vec, case_vec;
                                pcmpeqb.x result_nocase_vec, needle_vec, haystack_vec;

                                movdqa.x mask_vec, haystack_vec;
                                pcmpgtb.x mask_vec, z_vec;

                                movdqa.x bounds_vec, a_vec;
                                pcmpgtb.x bounds_vec, haystack_vec;
                                por.x mask_vec, bounds_vec;
                                pand.x result_cased_vec, mask_vec;

                                pcmpeqb.x bounds_vec, bounds_vec, bounds_vec;
                                pxor.x mask_vec, bounds_vec;

                                pand.x result_nocase_vec, mask_vec;
                                por.x result_cased_vec, result_nocase_vec;

                                pmovmskb.x found_gpr, result_cased_vec;
                                lzcnt.w index_gpr, found_gpr;
                                shl.d found_gpr, 16;
                                or.w found_gpr, index_gpr;
                                mov.d [results_data], found_gpr;
                            }

                            if results.found
                                return cast(int)(data - cast(u64)haystack.data + 15 - results.index), true;
                            else
                                data -= 16;
                        }

                        for < data + 15 .. max(data, end)
                            if compare.compare(<<cast(*u8)it, needle)
                                return cast(int)(it - cast(u64)haystack.data), true;
                    }

                case .AVX2;
                    if start_index >= 31 {
                        handled = true;

                        data := cast(u64)haystack.data + cast(u64)start_index - 31;
                        end := cast(u64)haystack.data;

                        needles : [32] u8 = ---;
                        memset(needles.data, needle, 32);
                        needle_data := needles.data;

                        case_bit :: 32;
                        case_bytes := #insert #run make_32(case_bit);
                        a_bytes    := #insert #run make_32(#char "a");
                        z_bytes    := #insert #run make_32(#char "z");

                        case_data := *case_bytes;
                        a_data := *a_bytes;
                        z_data := *z_bytes;

                        results : struct { index, found : u32; };
                        results_data := *results;

                        while data >= end {
                            #asm {
                                needle_vec: vec;
                                haystack_vec: vec;
                                case_vec: vec;
                                a_vec: vec;
                                z_vec: vec;
                                result_cased_vec: vec;
                                result_nocase_vec: vec;
                                bounds_vec: vec;
                                mask_vec: vec;
                                found_gpr: gpr;
                                index_gpr: gpr;

                                movdqu.y case_vec, [case_data];
                                movdqu.y a_vec, [a_data];
                                movdqu.y z_vec, [z_data];

                                movdqu.y needle_vec, [needle_data];
                                movdqu.y haystack_vec, [data];
                                pcmpeqb.y result_cased_vec, needle_vec, haystack_vec;

                                por.y haystack_vec, haystack_vec, case_vec;
                                por.y needle_vec, needle_vec, case_vec;
                                pcmpeqb.y result_nocase_vec, needle_vec, haystack_vec;

                                pcmpgtb.y mask_vec, haystack_vec, z_vec;

                                pcmpgtb.y bounds_vec, a_vec, haystack_vec;
                                por.y mask_vec, mask_vec, bounds_vec;
                                pand.y result_cased_vec, result_cased_vec, mask_vec;

                                pcmpeqb.y bounds_vec, bounds_vec, bounds_vec;
                                pxor.y mask_vec, mask_vec, bounds_vec;

                                pand.y result_nocase_vec, result_nocase_vec, mask_vec;
                                por.y result_cased_vec, result_cased_vec, result_nocase_vec;

                                pmovmskb.y found_gpr, result_cased_vec;
                                xor.q index_gpr, index_gpr;
                                lzcnt.d index_gpr, found_gpr;
                                shl.q found_gpr, 32;
                                or.q found_gpr, index_gpr;
                                mov.q [results_data], found_gpr;
                            }

                            if results.found
                                return cast(int)(data - cast(u64)haystack.data + 31 - results.index), true;
                            else
                                data -= 32;
                        }

                        for < data + 31 .. max(data, end)
                            if compare.compare(<<cast(*u8)it, needle)
                                return cast(int)(it - cast(u64)haystack.data), true;
                    }
            }
    }

    if !handled {
        for < cast(u64)haystack.data + cast(u64)start_index .. cast(u64)haystack.data
            if compare.compare(<<cast(*u8)it, needle)
                return cast(int)(it - cast(u64)haystack.data), true;
    }

    return -1, false;
}


last_index :: (haystack: string, needle: [] u8, compare: Character_Compare) -> index: int, found: bool {
    for < cast(u64)haystack.data + cast(u64)haystack.count - 1 .. cast(u64)haystack.data
        if is_any(<<cast(*u8)it, needle, compare)
            return cast(int)(it - cast(u64)haystack.data), true;

    return -1, false;
}


last_index :: (haystack: string, needle: [] u8, start_index : int, compare: Character_Compare) -> index: int, found: bool {
    if start_index == 0  return -1, false;

    start_index -= 1;
    validate_start_index(haystack);

    for < cast(u64)haystack.data + cast(u64)start_index .. cast(u64)haystack.data
        if is_any(<<cast(*u8)it, needle, compare)
            return cast(int)(it - cast(u64)haystack.data), true;

    return -1, false;
}


last_index :: inline (haystack: string, needle: string, start_index: int, index_proc : String_Index_Proc, compare: Character_Compare) -> index: int, found: bool {
    validate_start_index(haystack);
    if needle.count == 0 {
        return start_index, true;
    }
    else if needle.count == 1 {
        index, found := last_index(haystack, << needle.data, start_index, compare);
        return index, found;
    }
    else {
        index, found := index_proc(haystack, needle, start_index, compare);
        return index, found;
    }
}


last_index :: inline (haystack: string, needle: string, index_proc : String_Index_Proc, compare: Character_Compare) -> index: int, found: bool {
    index, found := last_index(haystack, needle, haystack.count, index_proc, compare);
    return index, found;
}


last_index :: inline (haystack: string, needle: string, start_index: int, $$index: Index_Proc) -> from_index: int, found: bool, to_index: int {
    from_index, to_index, found := index(haystack, needle, start_index, true);
    return from_index, found, to_index;
}


last_index :: inline (haystack: string, needle: string, $$index: Index_Proc) -> from_index: int, found: bool, to_index: int {
    from_index, to_index, found := index(haystack, needle, haystack.count, true);
    return from_index, found, to_index;
}



Split_By :: struct {
    text        : string;
    max_results : int;
    skip_empty  : bool;
    first_index : String_Index_Proc;
    last_index  : String_Index_Proc;
    compare     : Character_Compare;
}


Split_By_String :: struct {
    using base: Split_By;
    separator : string;
}


Split_By_Chars :: struct {
    using base: Split_By;
    separator : [] u8;
}


Split_By_Char :: struct {
    using base: Split_By;
    separator : u8;
}


Split_By_Index :: struct {
    using base: Split_By;
    indexes : [] int;
}


Split_By_Line :: struct {
    using base: Split_By;
    keep_eol := false;
}


Split_By_Proc :: struct {
    using base: Split_By;
    separator : string;
    index_proc : Index_Proc;
}


for_expansion :: (splitter: *Split_By_String, body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;
            index, found := last_index(splitter.text, splitter.separator, splitter.last_index, splitter.compare);
            while found {
                it = unsafe_slice(splitter.text, index + splitter.separator.count, end_index);
                end_index = index;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;

                index, found = last_index(splitter.text, splitter.separator, index, splitter.last_index, splitter.compare);
            }

            if process_remainder  it = unsafe_slice(splitter.text, 0, end_index);
        }
        else {
            start_index := 0;
            index, found := first_index(splitter.text, splitter.separator, splitter.first_index, splitter.compare);
            while found {
                it = unsafe_slice(splitter.text, start_index, index);
                start_index = index + splitter.separator.count;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;

                index, found = first_index(splitter.text, splitter.separator, start_index, splitter.first_index, splitter.compare);
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}


// @TODO update these for <

for_expansion :: (splitter: *Split_By_Proc, body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;
            from_index, to_index, found := splitter.index_proc(splitter.text, splitter.separator, splitter.text.count, true);
            while found {
                it = unsafe_slice(splitter.text, to_index, end_index);
                end_index = from_index;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;

                from_index, to_index, found = splitter.index_proc(splitter.text, splitter.separator, from_index, true);
            }

            if process_remainder  it = unsafe_slice(splitter.text, 0, end_index);
        }
        else {
            start_index := 0;
            from_index, to_index, found := splitter.index_proc(splitter.text, splitter.separator, 0, false);
            while found {
                it = unsafe_slice(splitter.text, start_index, from_index);
                start_index = to_index;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;

                from_index, to_index, found = splitter.index_proc(splitter.text, splitter.separator, to_index, false);
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}


for_expansion :: (splitter: *Split_By_Chars, body: Code, flags: For_Flags) #expand {
    #assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;
            for < index: splitter.text.count - 1 .. 0 {
                if is_any(splitter.text[index], splitter.separator) {
                    it = unsafe_slice(splitter.text, index + 1, end_index);
                    end_index = index;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;
                }
            }

            if process_remainder  it = unsafe_slice(splitter.text, 0, end_index);
        }
        else {
            start_index := 0;
            for index: 0 .. splitter.text.count - 1 {
                if is_any(splitter.text[index], splitter.separator) {
                    it = unsafe_slice(splitter.text, start_index, index);
                    start_index = index + 1;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;
                }
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}



for_expansion :: (splitter: *Split_By_Char, body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;
            for < index: splitter.text.count - 1 .. 0 {
                if splitter.text[index] == splitter.separator {
                    it = unsafe_slice(splitter.text, index + 1, end_index);
                    end_index = index;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;;
                }
            }

            if process_remainder  it = unsafe_slice(splitter.text, 0, end_index);
        }
        else {
            start_index := 0;
            for index: 0 .. splitter.text.count - 1 {
                if splitter.text[index] == splitter.separator {
                    it = unsafe_slice(splitter.text, start_index, index);
                    start_index = index + 1;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;
                }
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}


for_expansion :: (splitter: *Split_By_Index, body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;
            upper_bound := splitter.text.count;
            for < index, splitter_index: splitter.indexes {
                it, end_index = slice(splitter.text, index, end_index);
                if end_index < upper_bound
                    upper_bound = end_index;
                else
                    end_index = upper_bound;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;
            }

            if process_remainder  it = unsafe_slice(splitter.text, 0, end_index);
        }
        else {
            start_index := 0;
            lower_bound := 0;
            for index, splitter_index: splitter.indexes {
                _ : int;
                it, _, start_index = slice(splitter.text, start_index, index);
                if start_index > lower_bound
                    lower_bound = start_index;
                else
                    start_index = lower_bound;

                if splitter.skip_empty && it == ""  continue;

                it_index += 1;

                #insert body;

                if splitter.max_results != 0 && it_index >= max_it_index
                    break;
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}


for_expansion :: (splitter: *Split_By_Line, body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .POINTER));
    reverse := flags & .REVERSE;

    `it : string = ---;
    `it_index : int = -1;

    if splitter.max_results != 0 && splitter.max_results < 2 {
        it = splitter.text;
        it_index = 0;

        #insert body;
    }
    else {
        max_it_index := ifx splitter.max_results == 0 then 0 else splitter.max_results - 2;
        process_remainder := true;

        if reverse {
            end_index := splitter.text.count;

            for < index: splitter.text.count - 1 .. 0 {
                if splitter.text[index] == LF {
                    if splitter.keep_eol {
                        it = unsafe_slice(splitter.text, index + 1, end_index);
                    }
                    else {
                        it = unsafe_slice(splitter.text, end_index, index);
                        if ends_with(it, .[LF, CR])  it = unsafe_slice(it, 0, it.count - 1);
                    }
                    end_index = index + 1;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;
                }
            }
        }
        else {
            start_index := 0;

            for index: 0 .. splitter.text.count - 1 {
                if splitter.text[index] == LF {
                    if splitter.keep_eol {
                        it = unsafe_slice(splitter.text, start_index, index + 1);
                    }
                    else {
                        it = unsafe_slice(splitter.text, start_index, index);
                        if ends_with(it, CR)  it = unsafe_slice(it, 0, it.count - 1);
                    }
                    start_index = index + 1;

                    if splitter.skip_empty && it == ""  continue;

                    it_index += 1;

                    #insert body;

                    if splitter.max_results != 0 && it_index >= max_it_index
                        break;
                }
            }

            if process_remainder  it = unsafe_slice(splitter.text, start_index);
        }

        if process_remainder && (!splitter.skip_empty || it != "") {
            it_index += 1;

            #insert body;
        }
    }
}



slice :: inline (str: string, from_index: int, to_index: int) -> string, normalized_from_index: int, normalized_to_index: int {
    if from_index >= 0  from_index = min(from_index, str.count);
    else                from_index = clamp(str.count + from_index, 0, str.count);

    if to_index >= 0  to_index = min(to_index, str.count);
    else              to_index = clamp(str.count + to_index, 0, str.count);

    if from_index >= to_index  return "", from_index, to_index;

    result : string = ---;
    result.data = str.data + from_index;
    result.count = to_index - from_index;
    return result, from_index, to_index;
}


slice :: inline (str: string, from_index: int) -> string, normalized_from_index: int, normalized_to_index: int {
    result, normalized_from_index, normalized_to_index := slice(str, from_index, str.count);
    return result, normalized_from_index, normalized_to_index;
}


starts_with :: (haystack: string, needle: string) -> bool {
    if haystack.count < needle.count  return false;

    for 0 .. needle.count - 1
        if !default_compare.compare(haystack[it], needle[it])
            return false;

    return true;
}


starts_with :: inline (haystack: string, needle: u8) -> bool {
    return haystack.count > 0 && default_compare.compare(haystack[0], needle);
}


starts_with :: inline (haystack: string, needle: [] u8) -> bool {
    return haystack.count > 0 && is_any(haystack[0], needle, default_compare);
}



ends_with :: (haystack: string, needle: string) -> bool {
    if haystack.count < needle.count  return false;

    needle_index := 0;

    for haystack.count - needle.count .. haystack.count - 1 {
        if !default_compare.compare(haystack[it], needle[needle_index])
            return false;

        needle_index += 1;
    }

    return true;
}


ends_with :: inline (haystack: string, needle: u8) -> bool {
    return haystack.count > 0 && default_compare.compare(haystack[haystack.count - 1], needle);
}


ends_with :: inline (haystack: string, needle: [] u8) -> bool {
    return haystack.count > 0 && is_any(haystack[haystack.count - 1], needle, default_compare);
}


trim :: inline (str: string, char: u8) -> string {
    chars : [1] u8 = ---;
    chars[0] = char;
    return trim(str, chars);
}


trim :: (str: string) -> string {
    low_index := 0;
    high_index := str.count - 1;

    while low_index < str.count && str[low_index] <= SPACE
        low_index += 1;

    if low_index >= str.count  return "";

    while high_index > low_index && str[high_index] <= SPACE
        high_index -= 1;

    return unsafe_slice(str, low_index, high_index + 1);
}


trim :: (str: string, chars : [] u8) -> string {
    if chars.count == 0  return str;

    low_index := 0;
    high_index := str.count - 1;

    while low_index < str.count && is_any(str[low_index], chars, default_compare)
        low_index += 1;

    if low_index >= str.count  return "";

    while high_index > low_index && is_any(str[high_index], chars, default_compare)
        high_index -= 1;

    return unsafe_slice(str, low_index, high_index + 1);
}


trim :: (str: string, string_to_remove: string) -> string {
    if string_to_remove == ""  return str;

    s := str;
    while s.count > string_to_remove.count && starts_with(s, string_to_remove)
        s = unsafe_slice(s, string_to_remove.count);

    if !s  return "";

    while s.count > string_to_remove.count && ends_with(s, string_to_remove)
        s = unsafe_slice(s, 0, s.count - string_to_remove.count);

    return s;
}


trim_start :: inline (str: string, char: u8) -> string {
    chars : [1] u8 = ---;
    chars[0] = char;
    return trim_start(str, chars);
}


trim_start :: inline (str: string) -> string {
    index := 0;

    while index < str.count && str[index] <= SPACE
        index += 1;

    if index >= str.count  return "";

    return unsafe_slice(str, index);
}


trim_start :: inline (str: string, chars : [] u8) -> string {
    if chars.count == 0  return str;

    index := 0;

    while index < str.count && is_any(str[index], chars, default_compare)
        index += 1;

    if index >= str.count  return "";

    return unsafe_slice(str, index);
}


trim_start :: (str: string, string_to_remove: string) -> string {
    if string_to_remove == ""  return str;

    s := str;
    while s.count > string_to_remove.count && starts_with(s, string_to_remove)
        s = unsafe_slice(s, string_to_remove.count);

    return s;
}


trim_end :: inline (str: string, char: u8) -> string {
    chars : [1] u8 = ---;
    chars[0] = char;
    return trim_end(str, chars);
}


trim_end :: inline (str: string) -> string {
    index := str.count - 1;

    while index >= 0 && str[index] <= SPACE
        index -= 1;

    if index < 0  return "";

    return unsafe_slice(str, 0, index + 1);
}


trim_end :: inline (str: string, chars : [] u8) -> string {
    if chars.count == 0  return str;

    index := str.count - 1;

    while index >= 0 && is_any(str[index], chars, default_compare)
        index -= 1;

    if index < 0  return "";

    return unsafe_slice(str, 0, index + 1);
}


trim_end :: (str: string, string_to_remove: string) -> string {
    if string_to_remove == ""  return str;

    s := str;
    while s.count > string_to_remove.count && ends_with(s, string_to_remove)
        s = unsafe_slice(s, 0, s.count - string_to_remove.count);

    return s;
}


SPACE :: #char " ";



split_it :: (text: string, separator: string, skip_empty := false, max_results := 0) -> Split_By_String {
    result : Split_By_String = ---;
    fill_split_struct();
    result.separator = separator;
    return result;
}

fill_split_struct :: () #expand {
    `result.text = `text;
    `result.max_results = `max_results;
    `result.skip_empty = `skip_empty;
    `result.first_index = default_first_index;
    `result.last_index = default_last_index;
    `result.compare = default_compare;
}



default_first_index :: (haystack: string, needle: string, start_index: int, compare: Character_Compare) -> index: int, found: bool {
    if start_index > haystack.count - needle.count  return -1, false;

    end := cast(u64)haystack.data + cast(u64)(haystack.count - needle.count);
    needle_end := cast(u64)needle.count - 1;
    for start_of_word: cast(u64)haystack.data + cast(u64)start_index .. end {
        needle_index := needle.data;
        for character: start_of_word .. start_of_word + needle_end {
            if !compare.compare(<<cast(*u8)character, <<needle_index)
                continue start_of_word;
            needle_index += 1;
        }
        return cast(int)(start_of_word - cast(u64)haystack.data), true;
    }

    return -1, false;
}


default_last_index :: (haystack: string, needle: string, start_index: int, compare: Character_Compare) -> index: int, found: bool {
    if start_index < needle.count  return -1, false;

    start := cast(u64)haystack.data + cast(u64)(start_index - needle.count);
    needle_end := cast(u64)needle.count - 1;
    for < start_of_word: start .. cast(u64)haystack.data {
        needle_index := needle.data;
        for character: start_of_word .. start_of_word + needle_end {
            if !compare.compare(<<cast(*u8)character, <<needle_index)
                continue start_of_word;
            needle_index += 1;
        }
        return cast(int)(start_of_word - cast(u64)haystack.data), true;
    }

    return -1, false;
}


split :: inline (text: string, separator: $T, reversed := false, skip_empty := false, max_results := 0) -> [] string #must {
    result : [..] string;

    if reversed
        for < split_it(text, separator, skip_empty, max_results)
            array_add(*result, it);
    else
        for split_it(text, separator, skip_empty, max_results)
            array_add(*result, it);

    return result;
}


replace :: (haystack: string, needle: string, replacement: string, max_replacements := 0) -> string #must {
    if haystack == ""  return "";
    if needle == ""    return copy_string(haystack);

    result : String_Builder;
    init_string_builder(*result);

    first_loop := true;
    last_string := "";
    for split(haystack, needle, max_results = ifx max_replacements <= 0 then 0 else max_replacements + 1) {
        if first_loop  first_loop = false;
        else           append(*result, replacement);
        append(*result, it);
    }
    return builder_to_string(*result);
}


to_lower :: (str: string) {
    for 0 .. str.count - 1 {
        if str[it] >= #char "A" && str[it] <= #char "Z" {
            c : int = str[it] + #char "a" - #char "A";
            str[it] = cast(u8) c;
        }
    }
}


join :: (strings: [] string, separator: string) -> string #must {
    if strings.count == 0  return "";

    if strings.count == 1 {
        return copy_string(strings[0]);
    }

    count := separator.count * (strings.count - 1);
    for strings  count += it.count;

    joined := alloc_string(count, context.allocator, context.allocator_data);
    memcpy(joined.data, strings[0].data, strings[0].count);
    position := joined.data + strings[0].count;
    for 1 .. strings.count - 1 {
        if separator {
            memcpy(position, separator.data, separator.count);
            position += separator.count;
        }
        memcpy(position, strings[it].data, strings[it].count);
        position += strings[it].count;
    }

    return joined;
}


join :: inline (strings: [] string) -> string #must {
    return join(strings, "");
}


join :: (strings: [] string, separator: u8) -> string #must {
    return join(strings, string_from_char(*separator));
}


join :: (strings: .. string) -> string #must {
    return join(strings, "");
}


contains :: (haystack: string, needle: string) -> bool {
    _, found := first_index(haystack, needle, default_first_index, default_compare);
    return found;
}
