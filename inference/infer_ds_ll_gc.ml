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

open Owl
open Ds_distribution

(** Inference with streaming delayed sampling *)

type pstate = Infer_pf.pstate

(** Random variable of type ['b] and with parent of type ['a] *)
type ('p, 'a) ds_node =
  { ds_node_id : int;
    mutable ds_node_state : ('p, 'a) ds_state; }

and ('p, 'a) ds_state =
  | Initialized:
      ('z, 'p) ds_node * ('p, 'a) cdistr
      -> ('p, 'a) ds_state
  | Marginalized:
      'a mdistr * (('a, 'z) ds_node * ('a, 'z) cdistr) option
      -> ('p, 'a) ds_state
  | Realized of 'a


(** {2 Graph manipulations} *)

let fresh_id =
  let cpt = ref (-1) in
  fun () ->
    incr cpt;
    !cpt

(* initialize without parent node *)
let assume_constant : type a p.
  a mdistr -> (p, a) ds_node =
  fun d ->
  { ds_node_id = fresh_id ();
    ds_node_state = Marginalized (d, None); }

(* initialize with parent node *)
let assume_conditional : type a b c.
  (a, b) ds_node -> (b, c) cdistr -> (b, c) ds_node =
  fun p cdistr ->
  let child =
    { ds_node_id = fresh_id ();
      ds_node_state = Initialized (p, cdistr); }
  in
  child

let marginalize : type a b.
  (a, b) ds_node -> unit =
  fun n ->
  begin match n.ds_node_state with
  | Initialized (p, cdistr) ->
      begin match p.ds_node_state with
      | Realized x ->
          let mdistr = cdistr_to_mdistr cdistr x in
          n.ds_node_state <- Marginalized(mdistr, None)
      | Marginalized (p_mdistr, None) ->
          p.ds_node_state <- Marginalized (p_mdistr, Some(n, cdistr));
          let mdistr = make_marginal p_mdistr cdistr in
          n.ds_node_state <- Marginalized(mdistr, None)
      | Initialized _ | Marginalized (_, Some _) -> assert false
      end
  | Realized _ | Marginalized _ ->
      Format.eprintf "Error: marginalize@.";
      assert false
  end

let realize : type a b.
  b -> (a, b) ds_node -> unit =
  fun obs n ->
  assert begin match n.ds_node_state with
    | Marginalized (_mdistr, None) -> true
    | Initialized _ | Realized _ | Marginalized (_, Some _) -> false
  end;
  n.ds_node_state <- Realized obs


let force_condition : type a b.
  (a, b) ds_node -> unit =
  fun n ->
  begin match n.ds_node_state with
  | Marginalized (mdistr, Some(child, cdistr)) ->
      begin match child.ds_node_state with
      | Realized x ->
          let mdistr = make_conditional mdistr cdistr x in
          n.ds_node_state <- Marginalized(mdistr, None)
      | Initialized _ | Marginalized _ -> ()
      end
  | Initialized _ | Realized _ | Marginalized (_, None) -> ()
  end

let sample : type a b.
  (a, b) ds_node -> unit =
  fun n ->
  force_condition n;
  begin match n.ds_node_state with
  | Marginalized (m, None) ->
      let x = Distribution.draw m in
      realize x n
  | Realized _ -> ()
  | Initialized _  | Marginalized (_, Some _) -> assert false
  end

let factor' = Infer_pf.factor'
let factor = Infer_pf.factor

let observe : type a b.
  pstate -> b -> (a, b) ds_node -> unit =
  fun prob x n ->
  force_condition n;
  begin match n.ds_node_state with
  | Marginalized (mdistr, None) ->
      factor' (prob, Distribution.score(mdistr, x));
      realize x n
  | Initialized _ | Realized _ | Marginalized (_, Some _) -> assert false
  end

let rec prune : type a b.
  (a, b) ds_node -> unit =
  function n ->
    begin match n.ds_node_state with
    | Marginalized(_, Some(c, _)) -> prune c
    | Initialized _ | Realized _ | Marginalized (_, None) -> ()
    end;
    sample n

let rec graft : type a b.
  (a, b) ds_node -> unit =
  function n ->
    begin match n.ds_node_state with
    | Marginalized (_, None) | Realized _  -> ()
    | Marginalized (_, Some(c, _)) -> prune c
    | Initialized (p, _cdistr) ->
        graft p;
        force_condition p;
        marginalize n
    end

let rec value: type a b.
  (a, b) ds_node -> b =
  fun n ->
  begin match n.ds_node_state with
  | Realized x -> x
  | Marginalized _ | Initialized _ ->
      graft n;
      sample n;
      value n
  end

let rec get_mdistr : type a b.
  (a, b) ds_node -> b mdistr =
  function n ->
    force_condition n;
    begin match n.ds_node_state with
    | Marginalized (m, _) -> m
    | Initialized (p, cdistr) ->
        let p_mdistr = get_mdistr p in
        make_marginal p_mdistr cdistr
    | Realized _ -> assert false
    end

let get_distr : type a b.
  (a, b) ds_node -> b Distribution.t =
  fun n ->
  begin match n.ds_node_state with
  | Realized x -> Distribution.Dist_support [ (x, 1.) ]
  | Initialized _ | Marginalized _ -> get_mdistr n
  end

let observe_conditional : type a b c.
  pstate -> (a, b) ds_node -> (b, c) cdistr -> c -> unit =
  fun prob p cdistr obs ->
  let n = assume_conditional p cdistr in
  graft n;
  observe prob obs n

let get_distr_kind : type a b.
  (a, b) ds_node -> kdistr =
  fun n  ->
  begin match n.ds_node_state with
  | Initialized (_, AffineMeanGaussian _) -> KGaussian
  | Marginalized (Dist_gaussian _, _) -> KGaussian
  | Initialized (_, AffineMeanGaussianMV (_, _, _)) -> KMVGaussian
  | Marginalized (Dist_mv_gaussian (_, _), _) -> KMVGaussian
  | Initialized (_, CBernoulli) -> KBernoulli
  | Initialized (_, CBernBern _) -> KBernoulli
  | Marginalized (Dist_bernoulli _, _) -> KBernoulli
  | Marginalized (Dist_beta _, _) -> KBeta
  | Marginalized (( Dist_sampler _
                  | Dist_support _), _) -> KOthers
  | Marginalized (Dist_sampler_float _, _) -> KOthers
  | Marginalized (Dist_mixture _, _) -> KOthers
  | Marginalized (Dist_pair _, _) -> KOthers
  | Marginalized (Dist_list _, _) -> KOthers
  | Marginalized (Dist_array _, _) -> KOthers
  | Marginalized (Dist_uniform_int _, _) -> KOthers
  | Marginalized (Dist_uniform_float _, _) -> KOthers
  | Marginalized (Dist_exponential _, _) -> KOthers
  | Marginalized (Dist_poisson _, _) -> KOthers
  | Marginalized (Dist_add _, _) -> KOthers
  | Marginalized (Dist_mult _, _) -> KOthers
  | Marginalized (Dist_app _, _) -> KOthers
  | Realized _ -> assert false
  end

let shape : type a. ((a, Mat.mat) ds_node) -> int =
  fun r ->
  begin match r.ds_node_state with
  | Initialized (_, AffineMeanGaussianMV (_, b, _)) ->
      let rows, _ = Mat.shape b in rows
  | Marginalized (Dist_mv_gaussian(mu, _), _) ->
      let rows, _ = Mat.shape mu in rows
  | Realized v ->
      let rows, _ = Mat.shape v in rows
  | Initialized (_, _) -> assert false
  | Marginalized (_, _) -> assert false
  end


let is_realized : type p a. (p, a) ds_node -> bool =
  fun r ->
  begin match r.ds_node_state with
  | Initialized _ -> false
  | Marginalized _ -> false
  | Realized _ -> true
  end
