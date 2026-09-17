(* Rocq >= 9.1: Loadpath.vo_path has [installed], no [has_ml]. *)
let make ~unix_path ~coq_path : Loadpath.vo_path =
  { Loadpath.unix_path
  ; coq_path
  ; implicit = false
  ; recursive = true
  ; installed = false
  }
