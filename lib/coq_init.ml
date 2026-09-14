let init_coq ~debug ~record_comments =
  let load_module = Dynlink.loadfile in
  let load_plugin = Coq.Loader.plugin_handler None in
  let vm, warnings = (true, None) in
  Coq.Init.(
    coq_init { debug; record_comments; load_module; load_plugin; vm; warnings })

let io =
  let trace hdr ?verbose:_ msg =
    Format.eprintf "@[[trace] %s | %s @]@\n%!" hdr msg
  in
  let message ~lvl:_ ~message =
    Format.eprintf "@[[message] %s @]@\n%!" message
  in
  let diagnostics ~uri:_ ~version:_ _diags = () in
  let fileProgress ~uri:_ ~version:_ _pinfo = () in
  let perfData ~uri:_ ~version:_ _perf = () in
  let serverVersion _ = () in
  let serverStatus _ = () in
  let execInfo ~uri:_ ~version:_ ~range:_ = () in
  { Fleche.Io.CallBack.trace
  ; message
  ; diagnostics
  ; fileProgress
  ; perfData
  ; serverVersion
  ; serverStatus
  ; execInfo
  }

let init_st = ref None
let env = ref None

let setup_workspace ~token ~init ~debug ~cmdline ~root =
  let dir = Lang.LUri.File.to_string_file root in
  (let open Coq.Compat.Result.O in
   let+ workspace = Coq.Workspace.guess ~token ~debug ~cmdline ~dir () in
   let files = Coq.Files.make () in
   Fleche.Doc.Env.make ~init ~workspace ~files)
  |> Result.map_error (fun msg -> Petanque.Agent.Error.(make_request (coq msg)))

let uri_of_path path =
  let uri_str = Printf.sprintf "file://%s" path in
  let uri = Lang.LUri.of_string uri_str in
  Lang.LUri.File.of_uri uri
  |> Result.map_error (fun msg ->
         Petanque.Agent.Error.(make_request (system msg)))

let init_agent ~token ~debug ~record_comments ~cmdline ~root =
  init_st := Some (init_coq ~debug ~record_comments);
  Fleche.Io.CallBack.set io;
  let open Coq.Compat.Result.O in
  let init = Option.get !init_st in
  let* root_uri = uri_of_path root in
  let+ env_ = setup_workspace ~token ~init ~debug ~cmdline ~root:root_uri in
  env := Some env_

let pp_diag fmt { Lang.Diagnostic.message; _ } =
  Format.fprintf fmt "%a" Pp.pp_with message

let print_diags (doc : Fleche.Doc.t) =
  let d = Fleche.Doc.diags doc in
  Format.(eprintf "@[<v>%a@]" (pp_print_list pp_diag) d)

let read_raw ~uri =
  let file = Lang.LUri.File.to_string_file uri in
  try Ok Coq.Compat.Ocaml_414.In_channel.(with_open_text file input_all)
  with Sys_error err -> Error Petanque.Agent.Error.(make_request (system err))

let build_doc ~token ~uri =
  let current_env = Option.get !env in
  let fresh_env =
    Fleche.Doc.Env.make
      ~init:current_env.init
      ~workspace:current_env.workspace
      ~files:(Coq.Files.bump current_env.files)
  in
  env := Some fresh_env;
  Fleche.Memo.Intern.clear ();
  match read_raw ~uri with
  | Ok raw ->
    let languageId = "rocq" in
    let doc = Fleche.Doc.create ~token ~env:fresh_env ~uri ~languageId ~version:0 ~raw in
    print_diags doc;
    let target = Fleche.Doc.Target.End in
    Ok (Fleche.Doc.check ~io ~token ~target ~doc ())
  | Error err -> Error err

module SM = Lang.Compat.String.Map

type toc_entry =
  { info : Lang.Ast.Info.t list option
  ; statement : string option
  }

(* Fleche's toc maps every name reachable from a statement's [Info.t] to
   the node of that statement -- including names that only appear as
   [children] (record fields, inductive constructors, ...). Without this
   check, a record with N fields shows up as N+1 identical top-level
   entries, one per field plus one for the record itself. Keep an entry
   only when [name] is one of the statement's own top-level names, not a
   name it merely reports as a child. *)
let is_top_level_name ~name (info : Lang.Ast.Info.t list option) =
  match info with
  | None -> true
  | Some infos ->
    List.exists (fun (i : Lang.Ast.Info.t) -> i.name.v = Some name) infos

let toc_to_entry (name, node) =
  match Fleche.Doc.Node.ast node with
  | None -> None
  | Some ast ->
    let info = ast.Fleche.Doc.Node.Ast.ast_info in
    if not (is_top_level_name ~name info) then None
    else
      let statement =
        Some (Format.asprintf "%a" Pp.pp_with (Coq.Ast.print ast.v))
      in
      Some (name, { info; statement })

let doc_errors (doc : Fleche.Doc.t) =
  Fleche.Doc.diags doc
  |> List.filter Lang.Diagnostic.is_error
  |> List.map (fun d ->
    Format.asprintf "%a" Pp.pp_with d.Lang.Diagnostic.message)

let get_toc ~token:_ ~(doc : Fleche.Doc.t) :
    (string * toc_entry) list Petanque.Agent.R.t =
  let { Fleche.Doc.toc; _ } = doc in
  let toc = SM.bindings toc |> List.filter_map toc_to_entry in
  Ok toc
