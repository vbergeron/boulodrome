open Petanque

let unwrap_agent label = function
  | Ok v -> Ok v
  | Error e ->
    Error (Printf.sprintf "%s: %s" label (Agent.Error.to_string e.Request.Error.payload))

let uri_of_path path =
  let uri_str = Printf.sprintf "file://%s" path in
  let uri = Lang.LUri.of_string uri_str in
  match Lang.LUri.File.of_uri uri with
  | Ok f -> Ok f
  | Error msg -> Error (Printf.sprintf "Invalid path %s: %s" path msg)

let build_doc ~token path =
  match uri_of_path path with
  | Error e -> Error e
  | Ok uri ->
    (match Coq_init.build_doc ~token ~uri with
     | Ok doc -> Ok doc
     | Error e ->
       Error
         (Printf.sprintf "Failed to load %s: %s" path
            (Agent.Error.to_string e.Request.Error.payload)))

let format_doc_errors doc =
  match Coq_init.doc_errors doc with
  | [] -> ""
  | errs ->
    let unique = List.sort_uniq String.compare errs in
    let shown = List.filteri (fun i _ -> i < 10) unique in
    let suffix =
      let n = List.length unique - List.length shown in
      if n > 0 then [ Printf.sprintf "  ... and %d more" n ] else []
    in
    "\n\nDocument errors (may be the root cause):\n"
    ^ String.concat "\n" (List.map (fun e -> "  - " ^ e) shown @ suffix)
