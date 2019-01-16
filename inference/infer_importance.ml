open Ztypes
open Infer

type pstate = Infer.pstate

let sample = Infer.sample
let factor = Infer.factor



let infer_decay n decay (Node { alloc; reset; step }) =
  let alloc () =
    { infer_states = Array.init n (fun _ -> alloc ());
      infer_scores = Array.make n 0.0; }
  in
  let reset state =
    Array.iter reset state.infer_states;
    Array.fill state.infer_scores 0 n 0.0
  in
  let step { infer_states = states; infer_scores = scores } input =
    let values =
      Array.mapi
        (fun i state ->
          let value = step state ({ idx = i; scores = scores; }, input) in
          value)
        states
    in
    let weights, norm =
      let sum = ref 0. in
      let acc = ref [] in
      Array.iteri
        (fun i score ->
          let w = max (exp score) epsilon_float in
          acc := (values.(i), w) :: !acc;
          sum := !sum +. w)
        scores;
      (!acc, !sum)
    in
    if decay <> 1. then
      Array.iteri (fun i score -> scores.(i) <- decay *. score) scores;
    Distribution.Dist_support
      (List.map (fun (b, w) -> (b, w /. norm)) weights)
  in
  Node { alloc = alloc; reset = reset; step = step }


let infer n node =
  infer_decay n 1. node

