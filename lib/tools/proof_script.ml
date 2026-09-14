open Petanque

(* The committed tactics are already valid standalone sentences (each was
   run as one [Agent.run] call), so joining them with newlines, in the
   order they were committed, reproduces exactly what ran -- including any
   internal `;`-chaining across goals that a hand-transcribed,
   one-sentence-per-tactic script would silently break. This is a replay
   of what succeeded, not a reconstruction. *)
let run ~token ~session_id () =
  match Session.get_state session_id with
  | Error e -> Error (Session.error_to_string e)
  | Ok s ->
    (match Session.tactics session_id with
     | Error e -> Error (Session.error_to_string e)
     | Ok [] ->
       Ok
         (Printf.sprintf
            "No tactics have been committed yet in session '%s' (theorem \
             '%s' in %s)."
            session_id s.meta.theorem_name s.meta.file_path)
     | Ok tacs ->
       let script = String.concat "\n" tacs in
       let complete =
         match Agent.goals ~token ~st:s.current () with
         | Ok g -> Goal.are_complete g
         | Error _ -> false
       in
       let status =
         if complete then
           "All goals closed -- safe to close with Qed."
         else
           "Goals remain open -- this script alone will not close the \
            proof yet."
       in
       Ok
         (Printf.sprintf
            "Committed proof script for '%s' in %s\n%s\n\n\
             --- paste verbatim between `Proof.` and `Qed.` ---\n%s"
            s.meta.theorem_name s.meta.file_path status script))
