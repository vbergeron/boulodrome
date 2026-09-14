open Petanque

let status_of ~token (s : Session.session_state) =
  match Agent.goals ~token ~st:s.current () with
  | Ok g -> if Goal.are_complete g then "complete" else "in progress"
  | Error _ -> "unknown"

let format_one ~token (session_id, (s : Session.session_state)) =
  Printf.sprintf "- %s: %s (theorem '%s' in %s)" session_id (status_of ~token s)
    s.meta.theorem_name s.meta.file_path

let run ~token () =
  match Session.list () with
  | [] -> Ok "No open sessions."
  | sessions ->
    let n = List.length sessions in
    let lines = List.map (format_one ~token) sessions in
    Ok
      (Printf.sprintf "Open sessions (%d):\n%s" n (String.concat "\n" lines))
