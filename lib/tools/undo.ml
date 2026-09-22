open Petanque

let goals_text_of ~token st =
  match Agent.goals ~token ~st () with
  | Ok g -> Goal.format g
  | Error _ -> "(goals unavailable)"

let run ~token ~session_id ~steps () =
  match Session.undo session_id steps with
  | Error e -> Error e
  | Ok (actual, id, st) ->
    let goals_text = goals_text_of ~token st in
    let clamped =
      if actual < steps then
        Printf.sprintf " (requested %d, only %d in history)" steps actual
      else ""
    in
    Ok
      (Printf.sprintf "Undid %d step(s)%s. Now at state %d.\n%s" actual
         clamped id goals_text)

let run_to ~token ~session_id ~proof_state_id () =
  match Session.undo_to session_id proof_state_id with
  | Error e -> Error e
  | Ok st ->
    let goals_text = goals_text_of ~token st in
    Ok
      (Printf.sprintf "Restored proof state %d.\n%s" proof_state_id
         goals_text)
