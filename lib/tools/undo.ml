open Petanque

let run ~token ~session_id ~steps () =
  match Session.undo session_id steps with
  | Error e -> Error e
  | Ok (actual, st) ->
    let goals_text =
      match Agent.goals ~token ~st () with
      | Ok g -> Goal.format g
      | Error _ -> "(goals unavailable)"
    in
    let clamped =
      if actual < steps then
        Printf.sprintf " (requested %d, only %d in history)" steps actual
      else ""
    in
    Ok (Printf.sprintf "Undid %d step(s)%s.\n%s" actual clamped goals_text)
