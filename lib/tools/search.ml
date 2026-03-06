open Petanque

let run ~token ~session_id ~query () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    let tac =
      if String.contains query ' ' || String.contains query '"' then
        Printf.sprintf {|Search "%s".|} query
      else Printf.sprintf "Search %s." query
    in
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       Error
         (Printf.sprintf "Search error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok rr ->
       let results =
         List.map (fun (_lvl, msg) -> msg) rr.Agent.Run_result.feedback
       in
       let max_results = 50 in
       let shown = List.filteri (fun i _ -> i < max_results) results in
       let suffix =
         if List.length results > max_results then
           [ Printf.sprintf "... and %d more results"
               (List.length results - max_results)
           ]
         else []
       in
       if results = [] then Ok (Printf.sprintf "No results for: %s" query)
       else
         Ok
           (Printf.sprintf "Search results for '%s':\n%s" query
              (String.concat "\n" (shown @ suffix))))
