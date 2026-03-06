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
       let lines =
         List.map
           (fun (name, info_opt) ->
             match info_opt with
             | None -> Printf.sprintf "- %s" name
             | Some infos ->
               let details =
                 List.filter_map (fun (i : Lang.Ast.Info.t) -> i.detail) infos
               in
               (match details with
                | [] -> Printf.sprintf "- %s" name
                | d :: _ -> Printf.sprintf "- %s : %s" name d))
           entries
       in
       Ok
         (Printf.sprintf "Table of contents for %s:\n%s%s" file_path
            (String.concat "\n" lines)
            (Tools_helpers.format_doc_errors doc)))
