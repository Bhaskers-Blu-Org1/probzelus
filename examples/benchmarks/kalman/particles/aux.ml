open Infer_ds_nogc;;

(*
let read_val : unit -> (float * float) option =
    fun _ ->
    try
        Scanf.scanf "%f, %f\n" (fun t o -> Some (t, o))
    with End_of_file -> None
;;
*)

let read_val : unit ->  float * float =
    fun _ ->
        Scanf.scanf "%f, %f\n" (fun t o -> (t, o))
;;

let get_mean (type a) : (a, float) random_var -> float =
    fun r ->
        match r.state with
        | Marginalized (MGaussian (mu, sigma)) -> mu
        | _ -> assert false (* error *)
;;

let random_init : unit -> unit =
    fun _ ->
        Random.self_init ()
;;

let collect_garbage : unit -> unit =
    fun _ -> Gc.full_major ()
;;

let get_memory : unit -> float =
    fun _ ->
        let st = Gc.stat () in
        float_of_int st.live_words
;;

let get_time : unit -> float =
    fun _ ->
        Sys.time ()
;;
