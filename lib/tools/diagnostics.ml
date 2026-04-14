let severity_to_string = function
  | 1 -> "error"
  | 2 -> "warning"
  | 3 -> "information"
  | 4 -> "hint"
  | n -> Printf.sprintf "severity(%d)" n

let severity_of_string = function
  | "error" -> Ok (Some 1)
  | "warning" -> Ok (Some 2)
  | "information" -> Ok (Some 3)
  | "hint" -> Ok (Some 4)
  | s ->
    Error
      (Printf.sprintf
         "Unknown severity '%s'. Use \"error\", \"warning\", \"information\", \
          or \"hint\"."
         s)

let format_diag (d : Pp.t Lang.Diagnostic.t) =
  let range = d.Lang.Diagnostic.range in
  let sev = severity_to_string d.Lang.Diagnostic.severity in
  let msg = Format.asprintf "%a" Pp.pp_with d.Lang.Diagnostic.message in
  Printf.sprintf "l%dc%d-l%dc%d, %s: %s"
    (range.start.line + 1) range.start.character
    (range.end_.line + 1) range.end_.character
    sev msg

let run ~token ~file_path ?severity () =
  match Tools_helpers.build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    let diags = Fleche.Doc.diags doc in
    let diags =
      match severity with
      | Some sev ->
        List.filter
          (fun (d : Pp.t Lang.Diagnostic.t) -> d.severity = sev)
          diags
      | None -> diags
    in
    if diags = [] then Ok "No diagnostics."
    else
      Ok (String.concat "\n" (List.map format_diag diags))
