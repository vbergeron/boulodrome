open Petanque

let run ~token ~file_path ~theorem_name ~session_id ?pre_commands () =
  match Tools_helpers.build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    let result =
      Agent.start ~token ~doc ?pre_commands ~thm:theorem_name ()
    in
    (match Tools_helpers.unwrap_agent "start" result with
     | Error e -> Error (e ^ Tools_helpers.format_doc_errors doc)
     | Ok rr ->
       let goals_text =
         match Agent.goals ~token ~st:rr.Agent.Run_result.st () with
         | Ok g -> Goal.format g
         | Error _ -> "(goals unavailable)"
       in
       Session.create session_id ~file_path ~theorem_name rr.Agent.Run_result.st;
       let msg =
         Printf.sprintf
           "Started proof of '%s' in %s\nSession: %s\nProof finished: %b\n%s"
           theorem_name file_path session_id rr.Agent.Run_result.proof_finished
           goals_text
       in
       Ok msg)
