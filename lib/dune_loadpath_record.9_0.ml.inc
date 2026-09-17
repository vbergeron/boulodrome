(* Rocq 9.0: Loadpath.vo_path has neither [has_ml] nor [installed]. *)
let make ~unix_path ~coq_path : Loadpath.vo_path =
  { Loadpath.unix_path
  ; coq_path
  ; implicit = false
  ; recursive = true
  }
