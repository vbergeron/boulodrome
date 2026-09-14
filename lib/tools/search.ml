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
  | Session sid -> Result.map_error Session.error_to_string (Session.get sid)
  | File fp -> root_state ~token fp

let is_syntax_error e =
  Tools_helpers.contains ~needle:"Syntax error"
    (Agent.Error.to_string e.Request.Error.payload)

let is_wrapped q =
  let n = String.length q in
  n >= 2 && q.[0] = '(' && q.[n - 1] = ')'

(* A bare pattern whose top level uses an infix operator -- e.g. the
   sumbool type `{n < m} + {n = m} + {m < n}` -- isn't itself a single
   Rocq [search_item]: Rocq's Search grammar splits unparenthesized
   whitespace-separated tokens into several (conjunctive) query items, so
   a top-level `+` collides with that and Rocq reports a syntax error.
   Wrapping the whole query in parentheses makes it one term/search_item,
   which is what a query like this actually means. Retry that way before
   giving up, so patterns with top-level operators work without the
   caller having to know this quirk of the grammar. *)
let run ~token ~source ~query ~kind ?max_results () =
  match get_state ~token source with
  | Error e -> Error e
  | Ok st ->
    let cmd = command_of_kind kind in
    let exec q =
      let tac = Printf.sprintf "%s %s." cmd q in
      Agent.run ~token ~st ~tac ()
    in
    let wrapped, outcome =
      match exec query with
      | Ok rr -> false, Ok rr
      | Error e when is_syntax_error e && not (is_wrapped query) ->
        let wrapped_query = Printf.sprintf "(%s)" query in
        (match exec wrapped_query with
         | Ok rr -> true, Ok rr
         | Error _ -> false, Error e)
      | Error e -> false, Error e
    in
    (match outcome with
     | Error e ->
       let hint =
         if is_syntax_error e then
           Printf.sprintf
             "\nHint: if your query uses a top-level operator (e.g. `+`), \
              wrap the whole pattern in parentheses, e.g. \"(%s)\"."
             query
         else ""
       in
       Error
         (Printf.sprintf "Search error: %s%s"
            (Agent.Error.to_string e.Request.Error.payload)
            hint)
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
       let note =
         if wrapped then
           Printf.sprintf
             " (query auto-wrapped in parentheses as \"(%s)\")" query
         else ""
       in
       if results = [] then Ok (Printf.sprintf "No results for: %s%s" query note)
       else
         Ok
           (Printf.sprintf "Search results for '%s'%s:\n%s" query note
              (String.concat "\n" (shown @ suffix))))
