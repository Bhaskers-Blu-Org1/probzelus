(*
 * Copyright 2018-2020 IBM Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

open Probzelus
open Distribution
open Types

let () =
  Graphics.open_graph " 400x400";
  Graphics.auto_synchronize false

let clear () =
  Graphics.synchronize ();
  Graphics.clear_graph ()

let mouse_pos () =
  ignore (Graphics.wait_next_event [Graphics.Poll]);
  Graphics.mouse_pos ()

let draw_point color pos =
  begin match pos with
  | [ x ; y ] ->
      Graphics.set_color color;
      Graphics.draw_circle (int_of_float x) (int_of_float y) 2;
  | _ -> assert false
  end

let draw_obs color pos =
  begin match pos with
  | [ x ; y ] ->
      Graphics.set_color color;
      Graphics.fill_circle (int_of_float x) (int_of_float y) 8;
  | _ -> assert false
  end

let draw_point_dist dist =
  begin match dist with
  | Dist_support support ->
      let support =
        List.sort (fun (_, prob1) (_, prob2) -> compare prob1 prob2) support
      in
      let len = 1 + (List.length support / 200) in
      let color = ref (List.length support / len + 1)  in
      List.iteri
        (fun i (pos, prob) ->
           if i mod len = 0 then decr color;
           draw_point (Graphics.rgb !color !color !color) pos)
        support
  | _ -> assert false
  end

let () = Random.self_init()
let speed = [7.0; 7.0]
let p_noise = [5.0; 5.0]
let a_noise = [0.5; 0.5]
let p_init = [0.; 0.]

let observe_pos (x, y) =
  [ Distribution.draw (Distribution.gaussian (x, 5.));
    Distribution.draw (Distribution.gaussian (y, 5.)) ]

let observe_acc (x, y) =
  [ Distribution.draw (Distribution.gaussian (x, 0.01));
    Distribution.draw (Distribution.gaussian (y, 0.01)) ]

let ( +: ) a b = List.map2 (fun x y -> x +. y) a b
let ( -: ) a b = List.map2 (fun x y -> x -. y) a b
let ( *: ) a y = List.map (fun x -> x *. y) a
let norm a = sqrt (List.fold_left (fun acc x -> acc +. (x *. x)) 0. a)

let to_pair l =
  begin match l with
  | [ x; y; ] -> (x, y)
  | _ -> assert false
  end
