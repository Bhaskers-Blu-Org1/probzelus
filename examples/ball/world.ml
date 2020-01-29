let basket_x = 11.
let basket_y = 10.

let scale = 25

type 'a pres =
  | Pres of 'a
  | Abs

let ground (bumpers, x) =
  begin try
    let _, b_y =
      List.find (fun (b_x, _) -> b_x < x && x < b_x +. 1.) bumpers
    in
    b_y
  with Not_found ->
    neg_infinity
  end


let cross_y (bumpers, x, y, py) =
  begin try
    Pres
      (List.find
         (fun (bx, by) ->
            (bx <= x && x <= bx +. 1.) &&
            ((py < by && by <= y) || (py > by && by >= y)))
         bumpers)
  with Not_found ->
    Abs
  end


let move (last_bumpers, bumpers) =
  let last_bumpers = List.sort compare last_bumpers in
  let bumpers = List.sort compare bumpers in
  List.map2
    (fun (x1, y1) (x2, y2) ->
       (x1 +. 0.001 *. (x2 -. x1), y1 +. 0.001 *. (y2 -. y1)))
    last_bumpers bumpers

let () =
  Graphics.open_graph " 600x600";
  Graphics.set_window_title "Bouncing ball";
  Graphics.auto_synchronize false;
  ()

let to_int x =
  let x = 125. +. float scale *. x in
  int_of_float x

let w = 1 * scale

let show (bumpers, (x, y)) =
  Graphics.clear_graph ();
  Graphics.fill_rect (to_int basket_x) (to_int basket_y - 1) w 5;
  List.iter
    (fun (b_x, b_y) ->
       let x1, y1 = to_int b_x, to_int b_y - 1 in
       Graphics.fill_rect x1 y1 w 1)
    bumpers;
  Graphics.fill_circle (to_int x) (to_int y) 3;
  (* Graphics.synchronize (); *)
  ()
