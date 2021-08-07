#import "Basic";
#import "String";
#import "Hash_Table";
#import "Hash";

add :: (x: int, y: int) -> int {
    return x + y;
}

mul :: (x: int, y: int) -> int  {
    return x * y;
}

div :: (x: int, y: int) -> int  {
    return x / y;
}

sub :: (x: int, y: int) -> int {
    return x - y;
}


double :: (x: int) -> int, int {
    return x*2, x*4;
}



log :: (args: .. Any, separator := " ") {
    if args.count > 0       print("%",  args[0]);
    for i: 1..args.count-1  print("%1%2", separator, args[i]);
    print("\n");
}


//log :: () {
//    print("\n");
//}
//
//log :: (a: $A) {
//    print("%\n", a);
//}
//
//log :: (a: $A, b: $B) {
//    print("% %\n", a, b);
//}
//
//log :: (a: $A, b: $B, c: $C) {
//    print("% % %\n", a, b, c);
//}
//
//log :: (a: $A, b: $B, c: $C, d: $D) {
//    print("% % % %\n", a, b, c, d);
//}


gap :: () {
    print("\n\n");
}


//translate :: (view: $V, delta: int) {
//    //assert(view.)
//}

main :: () {
    operation := add;
    log("20?10 =", operation(20, 10));

    operation = mul;
    log("20?10 =", operation(20, 10));

    operation = div;
    log("20?10 =", operation(20, 10));

    operation = sub;
    log("20?10 =", operation(20, 10));

    gap();

    a := 1_000_000_000_000_000_000.0;
    log("u8 ", type_of(a) == u8);
    log("u16", type_of(a) == u16);
    log("u32", type_of(a) == u32);
    log("u64", type_of(a) == u64);
    log("s8 ", type_of(a) == s8);
    log("s16", type_of(a) == s16);
    log("s32", type_of(a) == s32);
    log("s64", type_of(a) == s64);
    log("s32", type_of(a) == s32);
    log("s64", type_of(a) == s64);
    log("f32", type_of(a) == float32);
    log("f64", type_of(a) == float64);

    gap();

    array: [10] int;

    for i: 0..9
        array[i] = i;

    for 0..9  array[it] = it * 10;
    //for array   log(it);

    for element, i: array  log(i, element);

    if array[0] != 0  log("How?");
    if array[0] == 0  log("Of course!");

    gap();

    view : [] int = array;
    for view  log(it);
    for it, i: array  log(i, it);

    gap();

    log(type_of(array), array.count, array.data);
    log(type_of(view), view.count, view.data);

    gap();

    foo: string = "foo";

    Bar :: struct {
        x: int;
        y: int;
    }

    bar: Bar;
    baz := bar;

    log(bar, *bar);
    log(baz, *baz);
    (x: Bar) { log(x, *x); }(bar);

    gap();

    Vector3 :: struct { x, y, z: float; }
    Other3  :: struct { x, y, z: float; }
    x: Vector3;
    //y: Vector3;
    y: Other3;

    operator== :: (a: Vector3, b: Vector3) -> bool {
        return a.x == b.x && a.y == b.y && a.z == b.z;
    }
    operator== :: (a: Vector3, b: Other3) -> bool {
        return a.x == b.x && a.y == b.y && a.z == b.z;
    }

    log(x == y);

    Line_Segment :: struct {
        start: Vector3;
        end:   Vector3;
        color: string;
    }

    line_segment: Line_Segment;
    line_segment = .{start = .{10, 20, 30}, end = .{}, color = "Hi"};
    log(line_segment);

    gap();

    types: [4] Type : .[int, float, float, bool];
    var: types[0];
    log(type_of(var));

//    V1 :: struct { type := V1; x := 0; }
//    V2 :: struct { using base: V1; base.type = V2; y := 0; }
//    V3 :: struct { using base: V2; base.type = V3; z := 0; }
//
//    v3: V3;
//    log(v3.type, v3.x, v3.y, v3.z);

    curious :: (pre: string, index: u16 = 0, post: string) {
        log(pre, index, post);
    }
    curious("Hello,", index = 0, "Sailor!");

    gap();

    anys: [3] Any;
    anys[0] = "Hello";
    anys[1] = 1;
    anys[2] = 10.5;

    for anys  print("% ", it); log();
    log(anys[0], anys[1], anys[2]);
    log(..anys);

    gap();

    log(((x,y) => x * y)(2, 3));

    run :: (proc: (x: int) -> int, arg: int) -> int{
        return proc(arg);
    }

    log(run(x => 2 * x, 5));

    gap();

    info_pointer := type_info(type_of(context));
    info := <<info_pointer;

    log(info.name);
    log(info_pointer.name);
    log();
    log(info.members);
    log(info_pointer.members);
    log();

    infoinfo := type_info(type_of(info));
    log(infoinfo.name);
    log(infoinfo.members);
    log();


}

Stuff :: enum u16 {
    FIRST  :: 0;
    SECOND :: 1;
    THIRD  :: 2;

    #if true {
        FOURTH :: 3;
    }
}



Omni :: struct {
    type: Type;
}

Omni_Int :: struct {
    using base: Omni;
    base.type = int;

    value: int;
}

Omni_Float :: struct {
    using base: Omni;
    base.type = float;

    value: float;
}


Person :: struct {
    forename: string;
    surname:  string;
}


mainx :: () {
    //a :: Stuff.[.THIRD, .SECOND, .FIRST, xx 7, .FOURTH];
    //log(type_of(a));
    //for a  log(it);

    s := join(.. .["foo", "bar", "puf"], ", ");
    log(s);

    s = join("foo", "bar", "puf", separator = ", ");
    log(s);


    s = join("foo", "bar", "puf", ", ");
    log(s);



    gap();

    table : Table(string, Any);
    table_set(*table, "int1", 1);
    table_set(*table, "float1", 10.5);
    table_set(*table, "string1", "foo");
    table_set(*table, "int2", 2);
    table_set(*table, "float2", 20.5);
    table_set(*table, "string2", "bar");

    max : float = 0.0;
    sum := 0;
    for value, key: table {
        if value.type.type == .INTEGER {
            x := << cast(*int) value.value_pointer;
            sum += x;
        }
        else if value.type.type == .FLOAT {
            x := << cast(*float) value.value_pointer;
            if x > max  max = x;
        }
        else
            log(value);
    }
    log("sum of ints:   ", sum);
    log("max of floats: ", max);

    gap();

    array: [..] string;
    array_add(*array, "Hello");
    log(array[0]);


    long_string :: #string ___
But really, "Sailor" is not a *u8, just ask the compiler!
To make this clearer, let's define a constant that is bound
to a string.  Because it's a constant, the compiler knows
it can never change, so it knows the actual string value,
and knows it's zero-terminated.
    ___;

    log(long_string);
}



xxxmain :: () {
    foo : int;
    bar : int = 10;
    baz := 10;

    log(foo, bar, baz);

    qux : float : 50.5;
    quux :: 50.5;

    gap();

    greet := () {
        log("Hello!");
    }

    greet();

    gap();

    test :: (loc := #caller_location) {
        log(loc);
    }

    test();
}

#import "Input";

S :: struct {
    a : int = 10;
    b : float = 0.5;
}

qux :: ($T: Type, a: T, b: T) {
    log(type_of(a), type_of(b));
    log(a, "+", b, "=", a+b);
}

xmain :: () {
    quux :: #bake_arguments qux(T=u32);
    quux(3, 6);
}

a :: 5;

map :: (array: [] $T, $result_type: Type, function: (T) -> result_type) -> [] result_type {
    result : [..] result_type;
    for array  array_add(*result, function(it));
    return result;
}



Alpha :: struct {
    foo : int;
}

Beta :: struct {
    foo : string;
}


xxmain :: () {
    alpha : Alpha;
    beta : Beta;
    using alpha;
    //using beta;
    print("%\n", foo);
}

strings_are_equal     :: (a: string, b: string) -> hi: bool #runtime_support #compiler;
strings_are_not_equal :: (a: string, b: string)  #runtime_support #compiler;
