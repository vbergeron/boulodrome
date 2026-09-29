(* Unit tests for pure helpers that need no running Rocq. *)

open Boulodrome

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n" name
  end

let parses s ~line ~col =
  check
    (Printf.sprintf "parse_position %S = l%dc%d" s line col)
    (match Start_proof.parse_position s with
     | Ok p -> p.Start_proof.line = line && p.Start_proof.col = col
     | Error _ -> false)

let rejects s =
  check
    (Printf.sprintf "parse_position %S is rejected" s)
    (Result.is_error (Start_proof.parse_position s))

let () =
  parses "l12c4" ~line:12 ~col:4;
  parses "l1c0" ~line:1 ~col:0;
  parses "  l7c3 " ~line:7 ~col:3;
  (* A full diagnostic range, as printed by rocq_diagnostics: start wins. *)
  parses "l12c4-l12c10" ~line:12 ~col:4;
  parses "l3c2-l5c0" ~line:3 ~col:2;
  rejects "";
  rejects "12:4";
  rejects "l0c4";
  rejects "l-1c4";
  rejects "l12";
  rejects "c4";
  rejects "l12c4x";
  rejects "l12c4-";
  rejects "L12C4";
  check "position_to_string round-trips"
    (Start_proof.position_to_string { Start_proof.line = 12; col = 4 }
     = "l12c4");
  if !failures > 0 then exit 1 else print_endline "All tests passed."
