let warmup = ref 0 in
let perf = ref false in
let input = ref "" in
let mem = ref false in

Arg.parse [
    ("-w", Set_int warmup, "Numberof warmup iterations");
    ("-perf", Unit (fun _ -> perf := true), "Performance testing");
    ("-mem", Unit (fun _ -> mem := true), "Memory performance testing");
] (fun s -> input := s) "";

let read_file fname =
    let stream = Scanf.Scanning.open_in fname in
    let rec read_file_helper _ =
        try 
            let s = Scanf.bscanf stream ("%f, %f\n") (fun t o -> (t, o)) in
            s :: read_file_helper ()
        with End_of_file -> []
    in
    read_file_helper ()
in

let run inp res =
    let Node{alloc; reset; step} = Kalman_ds.main in
    let state = alloc () in
    reset state;
    let iref = ref inp in
    let idx = ref 0 in

    while not (!iref = []) do
        match !iref with
        | [] -> assert false
        | i :: rest ->
            let time_pre = Sys.time () in
            let node, mse = step state i in
            let time = Sys.time () -. time_pre in
            iref := rest;
            Array.set res !idx ((string_of_float mse) ^ ", " ^ (string_of_float (time *. 1000.)) ^ "\n");
            idx := ((!idx) + 1);
    done
in

let runmem inp =
    let Node{alloc; reset; step} = Kalman_ds.main in
    let state = alloc () in
    reset state;
    let iref = ref inp in
    let idx = ref 0 in

    while not (!iref = []) do
        match !iref with
        | [] -> assert false
        | i :: rest ->
            let node, mse = step state i in
            Gc.full_major ();
            let st = Gc.stat () in
            let major_words = float_of_int (st.live_words) in
            let space = major_words in
            iref := rest;
            print_endline ((string_of_float mse) ^ ", " ^ (string_of_float (space /. 1000.)));
            (*Array.set res !idx (mse, major_words);*)
            idx := ((!idx) + 1);
    done
in



let runperf inp res idx =
    let Node{alloc; reset; step} = Kalman_ds.main in
    let state = alloc () in
    reset state;
    Random.self_init ();
    let iref = ref inp in

    while not (!iref = []) do
        match !iref with
        | [] -> assert false
        | i :: rest ->
            let time_pre = Sys.time () in
            let st = step state i in
            let time = Sys.time () -. time_pre in
            iref := rest;
            Array.set res !idx (time *. 1000.);
            idx := ((!idx) + 1);
    done
in

let stats arr =
    let upper_quantile = 0.9 in
    let lower_quantile = 0.1 in
    let middle_quantile = 0.5 in

    Array.sort compare arr;

    let upper_idx = truncate ((float_of_int (Array.length arr)) *. upper_quantile +. 0.5) in
    let lower_idx = truncate ((float_of_int (Array.length arr)) *. lower_quantile +. 0.5) in
    let middle_idx = truncate ((float_of_int (Array.length arr)) *. middle_quantile +. 0.5) in

    (Array.get arr lower_idx, Array.get arr middle_idx, Array.get arr upper_idx)
in

let do_runperf inp =
    let steps = List.length inp in
    let num_runs = 100 in
    let len = (steps * num_runs) in

    let ret : float array = Array.make len 0.0 in
    let idx = ref 0 in
    while not (!idx = len) do
        runperf inp ret idx
    done;
    assert (!idx = len);

    let agg : (float * float * float) array = Array.init steps (fun step ->
        let tmp : float array = Array.init num_runs (fun run ->
            Array.get ret (run * steps + step)
        )
        in
        stats tmp
    ) in
    agg
in


let rec do_runs n inp ret =
    if n = 0 then ()
    else (
        run inp ret;
        do_runs (n - 1) inp ret
    )
in


let inp = read_file !input in
let tmp : string array = Array.make (List.length inp) ("") in
do_runs !warmup inp tmp;

if !perf then (
    Array.iteri (fun i (low, mid, high) ->
        Printf.printf "%d, %f, %f, %f\n" i mid low high;
    ) (do_runperf inp)
) else (
    if !mem then (
        runmem inp;
        do_runs 1 inp tmp;
    ) else (
        let ret : string array = Array.make (List.length inp) ("") in
        let tmp : string array = Array.make (List.length inp) ("") in
        run inp ret;
        do_runs 1 inp tmp;
        print_string (String.concat "" (Array.to_list ret));
        flush stdout;
    )
);;
