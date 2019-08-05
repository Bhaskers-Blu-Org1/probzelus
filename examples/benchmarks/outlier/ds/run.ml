module M = struct
  type input = float * float
  type output = float Distribution.t
  let read_input () = Scanf.scanf ("%f, %f\n") (fun t o -> (t, o))
  let main = Outlier_ds.main
end

module H = Harness.Make(M)

let () =
  H.run ()
