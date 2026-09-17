(* Default shape for local `dune build` and CI (matches Rocq >= 9.1, the
   generic boulodrome.opam bound's default resolution). The 0.6.1+8.20 and
   0.6.1+9.0 opam-repository variants overwrite this file at `build:` time
   with dune_loadpath_record.{8_20,9_0}.ml.inc — see opam/. *)
let make ~unix_path ~coq_path : Loadpath.vo_path =
  { Loadpath.unix_path
  ; coq_path
  ; implicit = false
  ; recursive = true
  ; installed = false
  }
