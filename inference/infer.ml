(* A zelus discrete node is implemented by a value of the following type *)
(* see module Ztypes *)
(* type ('a, 'b) node =
    Node: { alloc : unit -> 's;   (* 's is the internal state *)
            reset: 's -> unit;    (* initializes the state *)
            step: 's -> 'a -> 'b; (* the step function *)
          } -> ('a, 'b) node
*)

open Ztypes

type pstate = {
  idx : int; (** particle index *)
  scores : float array; (** score of each particle *)
}

let factor (pstate, f0) =
  pstate.scores.(pstate.idx) <- pstate.scores.(pstate.idx) +. f0

let sample (pstate, dist) =
  Distribution.draw dist

type 'a infer_state = {
  infer_states : 'a array;
  infer_scores : float array;
}

let infer_subresample n (Node { alloc; reset; step }) =
    (* val infer :
         int -S-> (pstate * 'a -D-> 'b)
             -S-> bool * 'a -D-> 'b Distribution.t *)
    (* The infer function takes a number of particles, a node, and
       returns a node.  The node in argument takes as argument a state
       for the inference and an input and returns the output.
       The node in output takes as argument a boolen indiacting to the
       instants to resample and the input and returns the infered
       output. *)
  let alloc () =
    { infer_states = Array.init n (fun _ -> alloc ());
      infer_scores = Array.make n 0.0; }
  in
  let reset state =
    Array.iter reset state.infer_states;
    Array.fill state.infer_scores 0 n 0.0
  in
  let step { infer_states = states; infer_scores = scores } (c, input) =
    let values =
      Array.mapi
        (fun i state ->
          let value = step state ({ idx = i; scores = scores; }, input) in
          value)
        states
    in
    let ret = Normalize.normalize_nohist values scores in
    if c then Normalize.resample (states, scores, values);
    ret
  in
  Node { alloc = alloc; reset = reset; step = step }

let infer_dyn_resample n (Node { alloc; reset; step }) =
    (* val infer :
         int -S-> (pstate * 'a -D-> 'b)
             -S-> bool * 'a -D-> 'b Distribution.t *)
    (* The infer function takes a number of particles, a node, and
       returns a node.  The node in argument takes as argument a state
       for the inference and an input and returns the output.
       The node in output takes as argument a boolen indiacting to the
       instants to resample and the input and returns the infered
       output. *)
  let alloc () =
    { infer_states = Array.init n (fun _ -> alloc ());
      infer_scores = Array.make n 0.0; }
  in
  let reset state =
    Array.iter reset state.infer_states;
    Array.fill state.infer_scores 0 n 0.0
  in
  let step { infer_states = states; infer_scores = scores } (input) =
    let values =
      Array.mapi
        (fun i state ->
          let value = step state ({ idx = i; scores = scores; }, input) in
          value)
        states
    in
    let ret = Normalize.normalize_nohist values scores in


    let logsumexp scores = 
        let mscore = Array.fold_right (fun a b -> (max a b)) scores neg_infinity in
        let expscores = Array.map (fun score -> exp (score -. mscore)) scores in
        let sumexpscores = Array.fold_right (fun a b -> a+.b) expscores 0.0 in
        mscore +. (log sumexpscores)
    in

    let norm = logsumexp scores in
    let scores' = Array.map (fun score -> (score -. norm)) scores in

    let str = String.concat ", " (Array.to_list (Array.map (fun x -> (string_of_float x)) scores')) in

    let num = (((Array.fold_right (fun a b -> a +. b) (Array.map (fun x -> (exp x)) scores')) 0.) ** 2.) in
    let den = ((Array.fold_right (fun a b -> a +. b) (Array.map (fun x -> (exp x) ** 2.) scores')) 0.) in

    let ess = num /. den in


    if (ess < 0.3 *. (float_of_int n)) then  (
        Normalize.resample (states, scores, values);
    ) else ();
    ret
  in
  Node { alloc = alloc; reset = reset; step = step }



(*let infer n node =
  let Node { alloc; reset; step } = infer_subresample n node in
  Node { alloc;
         reset;
         step = (fun state input -> step state (true, input)); }
*)
let infer = infer_dyn_resample 

let infer_noresample n node =
  let Node { alloc; reset; step } = infer_subresample n node in
  Node { alloc;
         reset;
         step = (fun state input -> step state (false, input)); }




(* [memoize f x] is functionally equivalent to [f x] but stores *)
(* all the pairs (state, input) and the associated result *)
let memoize_step step (s, table) x =
  try
    Hashtbl.find table (s, x)
  with
  | Not_found ->
      let sc = Normalize.copy s in
      let o = step s x in
      Hashtbl.add table (sc, x) o;
      o

let memoize (Node { alloc; reset; step }) =
  let alloc () =
    alloc (), Hashtbl.create 7
  in
  let reset (s, table) =
    reset s; Hashtbl.clear table
  in
  Node { alloc = alloc; reset = reset; step = memoize_step step }



let expectation scores =
  let s = Array.fold_left (+.) 0. scores in
  s /. float (Array.length scores)


let plan_step n k model_step =
  let table = Hashtbl.create 7 in
  let rec expected_utility (state, score) (ttl, input) =
    if ttl < 1 then score
    else
      let states = Array.init n (fun _ -> Normalize.copy state) in
      let scores = Array.make n 0.0 in
      let score' =
        Array.iteri
          (fun i state ->
            let _ = model_step state ({ idx = i; scores = scores; }, input) in
            let score = scores.(i) in
            let eu =
              memoize_step
                expected_utility ((state, score), table) (ttl - 1, input)
            in
            scores.(i) <- eu)
          states;
        let scores' = Array.copy scores in
        Normalize.resample (states, scores, scores');
        expectation scores'
      in
      score +. score'
  in
  let step { infer_states = states; infer_scores = scores; } input =
    let values =
      Array.mapi
        (fun i state ->
          let value = model_step state ({ idx = i; scores = scores; }, input) in
          let score = scores.(i) in
          scores.(i) <- expected_utility (state, score) (k, input);
          value)
        states
    in
    let states_scores_values =
      Array.mapi (fun i state -> (state, scores.(i), values.(i))) states
    in
    Normalize.resample (states, scores, states_scores_values);
    Hashtbl.clear table;
    states_scores_values
  in
  step

(* [plan n k f x] runs n instances of [f] on the input stream *)
(* [x] but at each step, do a prediction of depth k *)
let plan n k (Node model : (pstate * 't1, 't2) Ztypes.node) =
  let alloc () = ref (model.alloc ()) in
  let reset state = model.reset !state in
  let step_body = plan_step n k model.step in
  let step plan_state input =
    let states = Array.init n (fun _ -> Normalize.copy !plan_state) in
    let scores = Array.make n 0.0 in
    let states_scores_values =
      step_body { infer_states = states; infer_scores = scores; } input
    in
    let dist = Normalize.normalize states_scores_values in
    let state', _, value = Distribution.draw dist in
    plan_state := state';
    value
  in
  Node { alloc = alloc; reset = reset; step = step }


type 'state infd_state =
    { infd_states : 'state array;
      infd_scores : float array; }

let infer_depth n k (Node model) =
  let alloc () =
    { infd_states = Array.init n (fun _ -> model.alloc ());
      infd_scores = Array.make n 0.0; }
  in
  let reset state =
    Array.iter model.reset state.infd_states;
    Array.fill state.infd_scores 0 n 0.0
  in
  let step infd_state input =
    let states_scores_values =
      plan_step n k
        model.step { infer_states = infd_state.infd_states;
                     infer_scores = infd_state.infd_scores; } input
    in
    let values = Array.map (fun (_, _, v) -> v) states_scores_values in
    Normalize.normalize values
  in
  Node { alloc = alloc; reset = reset; step = step }


let () = Random.self_init ()
