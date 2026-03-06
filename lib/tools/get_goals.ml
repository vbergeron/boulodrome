open Petanque

let run ~token ~session_id () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.goals ~token ~st () with
     | Error e ->
       Error
         (Printf.sprintf "Goals error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok g -> Ok (Goal.format g))

let premises ~token ~session_id () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.premises ~token ~st with
     | Error e ->
       Error
         (Printf.sprintf "Premises error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok premises ->
       let n = List.length premises in
       let shown = List.filteri (fun i _ -> i < 20) premises in
       let lines =
         List.mapi
           (fun i p ->
             Printf.sprintf "%d. %s (in %s)" (i + 1) p.Agent.Premise.full_name
               p.Agent.Premise.file)
           shown
       in
       let suffix =
         if n > 20 then
           [ Printf.sprintf "... and %d more premises" (n - 20) ]
         else []
       in
       Ok
         (Printf.sprintf "Available premises (%d total):\n%s" n
            (String.concat "\n" (lines @ suffix))))
