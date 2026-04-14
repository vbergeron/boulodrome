let format_entry (name, (entry : Coq_init.toc_entry)) =
  let kind =
    match entry.info with
    | Some (info :: _) ->
      (match info.detail with Some d -> d | None -> "?")
    | _ -> "?"
  in
  let children =
    match entry.info with
    | Some (info :: _) ->
      (match info.children with
       | Some cs ->
         let names =
           List.filter_map (fun (c : Lang.Ast.Info.t) -> c.name.v) cs
         in
         if names = [] then ""
         else " { " ^ String.concat ", " names ^ " }"
       | None -> "")
    | _ -> ""
  in
  let line =
    match entry.info with
    | Some (info :: _) -> Printf.sprintf " (line %d)" (info.range.start.line + 1)
    | _ -> ""
  in
  let stmt =
    match entry.statement with
    | Some s -> "\n    " ^ s
    | None -> ""
  in
  Printf.sprintf "- [%s] %s%s%s%s" kind name children line stmt

let run ~token ~file_path () =
  match Tools_helpers.build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    (match Coq_init.get_toc ~token ~doc with
     | Error e ->
       Error
         (Printf.sprintf "TOC error: %s"
            (Petanque.Agent.Error.to_string e.Request.Error.payload))
     | Ok entries ->
       let lines = List.map format_entry entries in
       Ok
         (Printf.sprintf "Table of contents for %s:\n%s%s" file_path
            (String.concat "\n" lines)
            (Tools_helpers.format_doc_errors doc)))
