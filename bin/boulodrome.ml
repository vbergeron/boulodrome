let () =
  (* Route logs to stderr so stdout stays clean for the MCP JSON-RPC stream *)
  let log_file = open_out "/tmp/boulodrome.log" in
  let log_fmt = Format.formatter_of_out_channel log_file in
  let reporter =
    let report _src level ~over k msgf =
      let k _ = over (); k () in
      msgf @@ fun ?header:_ ?tags:_ fmt ->
      Format.kfprintf k log_fmt
        ("%a @[" ^^ fmt ^^ "@]@.")
        Logs.pp_level level
    in
    { Logs.report }
  in
  Logs.set_reporter reporter;
  Logs.set_level (Some Logs.Debug);

  (* Initialise the Coq limits backend (must be called once) *)
  Coq.Limits.select_best None;
  let token = Coq.Limits.Token.create () in

  (* Discover workspace root from argv, defaulting to cwd *)
  let root =
    match Array.to_list Sys.argv |> List.tl with
    | [] -> Sys.getcwd ()
    | dir :: _ -> dir
  in

  (* Auto-discover loadpaths from dune theory stanzas *)
  let vo_load_path = Boulodrome.Dune_loadpath.discover ~root in
  List.iter
    (fun (p : Loadpath.vo_path) ->
      Logs.info (fun m ->
          m "Loadpath: %s -> %s" p.unix_path
            (Names.DirPath.to_string p.coq_path)))
    vo_load_path;
  let cmdline : Coq.Workspace.CmdLine.t =
    { coqlib = Coq.Args.coqlib_dyn
    ; findlib_config = None
    ; ocamlpath = []
    ; vo_load_path
    ; args = []
    ; require_libraries = []
    }
  in

  (* Boot the Coq kernel and set up the workspace *)
  (match
     Boulodrome.Coq_init.init_agent ~token ~debug:false ~record_comments:false
       ~cmdline ~root
   with
  | Error e ->
    let msg =
      Petanque.Agent.Error.to_string e.Request.Error.payload
    in
    Logs.err (fun m -> m "Failed to initialise Coq: %s" msg);
    exit 1
  | Ok () -> ());

  Boulodrome.Mcp_server.run ~token ()
