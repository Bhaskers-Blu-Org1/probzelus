(** Inference with delayed sampling with less pointers low level interface *)

type pstate = Infer_pf.pstate

type mgaussiant = float
type mbetat = float
type mbernoullit = bool
type 'a mtype = 'a

(** Family of marginal distributions (used as kind) *)
type marginal_t =
  | MGaussianT
  | MBetaT
  | MBernoulliT

(** Marginalized distribution *)
type 'a mdistr =
  | MGaussian : float * float -> mgaussiant mdistr
  | MBeta : float * float -> mbetat mdistr
  | MBernoulli : float -> bool mdistr

(** Conditionned distribution *)
type ('m1, 'm2) cdistr =
  | AffineMeanGaussian: float * float * float -> (mgaussiant, mgaussiant) cdistr
  | CBernoulli : (mbetat, mbernoullit) cdistr

(** Random variable of type ['b] and with parent of type ['a] *)
type ('a, 'b) rv =
  { mutable state : 'b rv_state;
    mutable distr : ('a, 'b) dsdistr;
  }

and 'a rv_state =
  | Initialized
  | Marginalized : (('a, 'b) cdistr * ('a,'b) rv) option -> 'a rv_state
  | Realized of 'a mtype

and ('a, 'b) dsdistr =
  | UDistr :  'b mdistr -> ('a, 'b) dsdistr
    (** unconditional distribution *)
  | CDistr : ('z, 'm1) rv * ('m1, 'm2) cdistr -> ('m1, 'm2) dsdistr
    (** conditional distribution *)

and 'b rv_from =
  RV_from : ('b, 'c) rv -> 'b rv_from

let type_of_mdistr (type a): a mdistr -> marginal_t =
  fun mdistr ->
  begin match mdistr with
    | MGaussian _ -> MGaussianT
    | MBeta _ -> MBetaT
    | MBernoulli _ -> MBernoulliT
  end

let type_of_cdistr (type a b): (a, b) cdistr -> marginal_t =
  fun  cdist ->
  begin match cdist with
    | AffineMeanGaussian _ -> MGaussianT
    | CBernoulli -> MBernoulliT
  end

let type_of_dsdistr (type a) (type b): (a, b) dsdistr -> marginal_t =
  fun dsdistr ->
  begin match dsdistr with
  | UDistr d -> type_of_mdistr d
  | CDistr (_, d) -> type_of_cdistr d
  end

let mdistr_to_distr (type a): a mdistr -> a Distribution.t = fun mdistr ->
  begin match mdistr with
    | MGaussian (mu, var) -> Distribution.gaussian(mu, sqrt var)
    | MBeta (alpha, beta) -> Distribution.beta(alpha, beta)
    | MBernoulli p -> Distribution.bernoulli p
  end

let cdistr_to_mdistr (type m) (type m'):
  (m, m') cdistr -> m mtype -> m' mdistr =
  fun cdistr obs ->
  begin match cdistr with
    | AffineMeanGaussian (m, b, obsvar) ->
        MGaussian (m *. obs +. b, obsvar)
    | CBernoulli ->
        MBernoulli obs
  end


let mgaussian mu var = MGaussian (mu, var)
let mbeta alpha beta = MBeta (alpha, beta)
let mbernoulli theta = MBernoulli theta

let cbernoulli = CBernoulli
let affine_mean_gaussian m b var = AffineMeanGaussian (m, b, var)

let gaussian_mean_gaussian: float -> (mgaussiant, mgaussiant) cdistr =
  fun x ->
  AffineMeanGaussian (1., 0., x)

let make_marginal (type a) (type b): a mdistr -> (a, b) cdistr -> b mdistr =
  fun mdistr cdistr ->
  begin match mdistr, cdistr with
    | MGaussian (mu, var), AffineMeanGaussian(m, b, obsvar) ->
        MGaussian (m *. mu +. b, m ** 2. *. var +. obsvar)
    | MBeta (a, b),  CBernoulli ->
        MBernoulli (a /. (a +. b))
    | _ -> assert false (* error "impossible" *)
  end

let make_conditional (type a) (type b):
  a mdistr -> (a, b) cdistr -> b mtype -> a mdistr =
  let gaussian_conditioning mu var obs obsvar =
    let ivar = 1. /. var in
    let iobsvar = 1. /. obsvar in
    let inf = ivar +. iobsvar in
    let var' = 1. /. inf in
    let mu' = (ivar *. mu +. iobsvar *. obs) /. inf in
    (mu', var')
  in
  fun mdistr cdistr obs ->
  begin match mdistr, cdistr with
    | MGaussian(mu, var), AffineMeanGaussian(m, b, obsvar) ->
        let (mu', var') =
          gaussian_conditioning mu var ((obs -. b) /. m) (obsvar /. m ** 2.)
        in
        MGaussian(mu', var')
    | MBeta (a, b),  CBernoulli ->
        if obs then MBeta (a +. 1., b) else MBeta (a, b +. 1.)
    | _, _ -> assert false (* error "impossible" *)
  end


(* initialize without parent node *)
let assume_constant (type a) (type z): a mdistr -> (z, a) rv =
  fun d ->
  (* Format.eprintf "assume_constant %s@." n; *)
  let ret =
  { state = Marginalized None;
    distr = UDistr d; }
  in
  ret
;;

(* initialize with parent node *)
let assume_conditional (type a) (type b) (type c):
  (a,b) rv -> (b, c) cdistr -> (b, c) rv =
  fun par cdistr ->
  let child =
    { state = Initialized;
      distr = CDistr (par, cdistr); }
  in
  child

let do_condition node =
  begin match node.state, node.distr with
    | (Marginalized (Some (cdistr, c)), UDistr pardistr) ->
        begin match c.state with
        | Realized x ->
            node.state <- Marginalized None;
            node.distr <- UDistr (make_conditional pardistr cdistr x);
        | _ -> assert false
        end
    | _ -> assert false
  end

let marginalize (type a) (type b): (a, b) rv -> unit =
  fun n ->
  (*Format.eprintf "marginalize: %s@." n.name;*)
  begin match n.state, n.distr with
    | Initialized, CDistr (par, cdistr) ->
        let marg, new_parstate =
          begin match par.state, par.distr with
            | (Realized x, _) ->
                (cdistr_to_mdistr cdistr x, Realized x)
            | (Marginalized None, UDistr par_marginal) ->
                (make_marginal par_marginal cdistr, Marginalized (Some (cdistr, n)))
            | (Marginalized _, _)
            | (Initialized, _) -> assert false (* error "marginalize'" *)
          end
        in
        n.state <- Marginalized None;
        n.distr <- UDistr marg;
        par.state <- new_parstate
    | state, _ ->
        (*Format.eprintf "Error: marginalize %s@." n.name;*)
        assert false
  end

let realize (type a) (type b): b mtype -> (a, b) rv -> unit =
  fun val_ n ->
  (*Format.eprintf "realize: %s@." n.name;*)
  (* ioAssert (isTerminal n) *)
  begin match n.state with
    | Marginalized (Some (cdistr, ch)) ->
      ch.distr <- UDistr (cdistr_to_mdistr cdistr val_);
      let rec fixup_marginalize node =
          begin match node.state, node.distr with
            | (Marginalized (Some (cdistr, child)), UDistr node_distr) ->
              child.distr <- UDistr (make_marginal node_distr cdistr)
            | _ -> ()
          end
      in
      fixup_marginalize ch
    | _ -> ()
  end;
  n.state <- Realized val_

let sample (type a) (type b) : (a, b) rv -> unit =
  fun n ->
  (* Format.eprintf "sample: %s@." n.name; *)
  (* ioAssert (isTerminal n) *)
  begin match n.state, n.distr with
    | (Marginalized None, UDistr m) ->
        let x = Distribution.draw (mdistr_to_distr m) in
        realize x n
    | _ -> assert false (* error "sample" *)
  end

let factor' = Infer_pf.factor'
let factor = Infer_pf.factor

let observe (type a) (type b): pstate -> b mtype -> (a, b) rv -> unit =
  fun prob x n ->
  (* io $ ioAssert (isTerminal n) *)
  (*Format.eprintf "observe %s@." n.name; *)
  begin match n.state, n.distr with
    | (Marginalized None, UDistr m) ->
        factor' (prob, Distribution.score(mdistr_to_distr m, x));
        realize x n
    | _ -> assert false (* error "observe'" *)
  end

let is_marginalized state =
  begin match state with
  | Marginalized _ -> true
  | _ -> false
  end

let rec prune : 'a 'b. ('a, 'b) rv -> unit = function n ->
  (*Format.eprintf "prune: %s@." n.name;*)
  (* assert (isMarginalized (state n)) $ do *)
  begin match n.state with
  | Marginalized (Some (distr, mchild)) ->
    begin match mchild.state with
    | Marginalized _ ->
      prune  mchild;
      sample mchild;
      do_condition n
    | Realized x ->
      do_condition n
    | Initialized -> ()
    end
  | Marginalized None -> ()
  | _ -> assert false
  end
;;


let rec graft : 'a 'b. ('a, 'b) rv -> unit = function n ->
  (*Format.eprintf "graft %s@." n.name; *)
  begin match n.state with
  | Marginalized _ ->
      prune n
  | _ ->
      begin match n.distr with
        | UDistr _ -> assert false (* error "graft" *)
        | CDistr (par, cdistr) ->
            graft par;
            marginalize n
      end
  end
;;

(* Turn as many nodes into terminal nodes as we can without sampling *)
let rec nondestructive_graft : 'a 'b. ('a, 'b) rv -> unit = fun n ->
  let rec nondestructive_prune : 'a 'b. ('a, 'b) rv -> unit = fun n ->
    begin match n.state with
      | Marginalized (Some (distr, mchild)) ->
          begin match mchild.state with
            | Marginalized _ ->
                nondestructive_prune mchild
            | Realized x ->
                do_condition n
            | Initialized -> ()
          end
      | Marginalized None -> ()
      | _ -> assert false
    end
  in
  begin match n.state with
    | Marginalized _ -> nondestructive_prune n
    | _ ->
        begin match n.distr with
          | UDistr _ -> ()
          | CDistr (par, cdistr) ->
              nondestructive_graft par
        end
  end

let get_conditional (type a) (type b):  (a, b) rv -> (a, b) rv =
  fun rv ->
  graft rv;
  rv

let obs (type a) (type b): pstate -> b mtype -> (a, b) rv -> unit =
  fun prob x n ->
  (*Format.eprintf "obs %s@." n.name;*)
  graft n;
  observe prob x n

let rec value: 'a 'b. ('a, 'b) rv -> 'b mtype =
  fun n ->
  begin match n.state with
    | Realized x -> x
    | _ ->
        graft n;
        sample n;
        value n
  end

let fvalue: 'a 'b. ('a, 'b) rv -> 'b mtype =
  fun n ->
  value (Normalize.copy n)

let distribution_of_rv : type a b. (a, b) rv -> b Distribution.t =
  fun n ->
    begin match n.state with
    | Realized x -> Distribution.Dist_support [ (x, 1.) ]
    | _ ->
        let n = Normalize.copy n in
        graft n;
        begin match n.state, n.distr with
        | Marginalized None, UDistr m ->
            begin match m with
            | MGaussian (mu, sigma) -> Distribution.gaussian(mu, sigma)
            | MBeta (a, b) -> Distribution.beta(a, b)
            | MBernoulli p -> Distribution.bernoulli p
            end
        | _, _ -> assert false
        end
  end

let draw (type a) (type b) : (a, b) rv -> b mtype =
  fun n ->
  (* Format.eprintf "draw: %s@." n.name; *)
  (* ioAssert (isTerminal n) *)
  begin match n.distr with
    | UDistr distr ->
        Distribution.draw (mdistr_to_distr distr)
    | _ -> assert false (* error "sample" *)
  end


let observe_conditional (type a) (type b) (type c):
  pstate -> (a, b) rv -> (b, c) cdistr -> c mtype -> unit =
  fun prob n cdistr observation ->
  let y = assume_conditional n cdistr in
  obs prob observation y




(* ----------------------------------------------------------------------- *)
(* Examples *)

(* let delay_triplet zobs = *)
(*   let prob = { score = 0. } in *)
(*   let x = assume_constant "x" (MGaussian (0., 1.)) in *)
(*   Format.printf "x created@."; *)
(*   let y = assume_conditional "y"  x (gaussian_mean_gaussian 1.) in *)
(*   Format.printf "y created@."; *)
(*   let z = assume_conditional "z" y (gaussian_mean_gaussian 1.) in *)
(*   Format.printf "z created@."; *)
(*   obs prob zobs z; *)
(*   Format.printf "z observed@."; *)
(*   Format.printf "%f@." (get_value z); *)
(*   Format.printf "%f@." (get_value x); *)
(*   Format.printf "%f@." (get_value y) *)

(* let () = *)
(*   Random.self_init (); *)
(*   delay_triplet 42. *)

(* let obs_sample xobs = *)
(*   let prob = { Infer_pf.scores = [| 0. |]; idx = 0 } in *)
(*   let x = assume_constant "x" (MGaussian (0., 1.)) in *)
(*   Format.printf "x created@."; *)
(*   obs prob xobs x; *)
(*   Format.printf "x observed@."; *)
(*   sample x; *)
(*   Format.printf "x sampled@."; *)
(*   Format.printf "%f@." (get_value x) *)

(* let () = *)
(*   Random.self_init (); *)
(*   obs_sample 42. *)
