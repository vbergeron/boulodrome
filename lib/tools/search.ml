open Petanque

type kind = Search | SearchPattern | SearchRewrite

let kind_of_string = function
  | "search_pattern" -> Ok SearchPattern
  | "search_rewrite" -> Ok SearchRewrite
  | "search" -> Ok Search
  | s -> Error (Printf.sprintf "Unknown search kind '%s'. Use \"search\", \"search_pattern\", or \"search_rewrite\"." s)

let command_of_kind = function
  | Search -> "Search"
  | SearchPattern -> "SearchPattern"
  | SearchRewrite -> "SearchRewrite"

type source = Session of string | File of string

let source_of_args ~session_id ~file_path =
  match session_id, file_path with
  | Some sid, _ -> Ok (Session sid)
  | None, Some fp -> Ok (File fp)
  | None, None -> Error "Provide either session_id or file_path"

let root_state ~token fp =
  match Tools_helpers.build_doc ~token fp with
  | Error e -> Error e
  | Ok doc ->
    (match Agent.get_root_state ~doc () with
     | Ok rr -> Ok rr.Agent.Run_result.st
     | Error e ->
       Error
         (Printf.sprintf "Failed to get state from %s: %s" fp
            (Agent.Error.to_string e.Request.Error.payload)))

let get_state ~token = function
  | Session sid -> Session.get sid
  | File fp -> root_state ~token fp

let run ~token ~source ~query ~kind ?max_results () =
  match get_state ~token source with
  | Error e -> Error e
  | Ok st ->
    let cmd = command_of_kind kind in
    let tac = Printf.sprintf "%s %s." cmd query in
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       Error
         (Printf.sprintf "Search error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok rr ->
       let results =
         List.map (fun (_lvl, msg) -> msg) rr.Agent.Run_result.feedback
       in
       let max_results = match max_results with Some n -> n | None -> 30 in
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
