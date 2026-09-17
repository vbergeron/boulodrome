(* Rocq/Coq 8.20: Loadpath.vo_path has [has_ml], no [installed]. *)
let make ~unix_path ~coq_path : Loadpath.vo_path =
  { Loadpath.unix_path
  ; coq_path
  ; implicit = false
  ; has_ml = false
  ; recursive = true
  }
