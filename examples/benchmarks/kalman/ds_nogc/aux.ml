open Infer_ds_ll;;

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

let get_mean (type a) : float Infer_ds.expr -> float =
    fun e ->
        begin match e with
        | Ervar (RV r) ->
            begin match r.state with
            | Marginalized (MGaussian (mu, sigma)) -> mu
            | _ -> assert false (* error *)
            end
        | _ -> assert false
        end
;;

let collect_garbage : unit -> unit =
    fun _ -> Gc.full_major ()
;;

let get_memory : unit -> float =
    fun _ ->
        (*let st = Gc.stat () in
        float_of_int st.live_words*) 0.0
;;

let get_time : unit -> float =
    fun _ ->
        (* Sys.time () *) 0.0
;;
