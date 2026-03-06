(** Generic MCP server: JSON-RPC 2.0 over stdio with Content-Length framing. *)

(* ------------------------------------------------------------------ *)
(* I/O framing (same as LSP)                                           *)
(* ------------------------------------------------------------------ *)

let read_message () =
  let line = input_line stdin in
  let line = String.trim line in
  if String.length line > 0 && line.[0] = '{' then
    Yojson.Safe.from_string line
  else begin
    let content_length = ref 0 in
    let parse_header h =
      match String.split_on_char ':' h with
      | key :: rest when String.trim key = "Content-Length" ->
        content_length := int_of_string (String.trim (String.concat ":" rest))
      | _ -> ()
    in
    parse_header line;
    let rec drain_headers () =
      let h = String.trim (input_line stdin) in
      if h = "" then ()
      else begin parse_header h; drain_headers () end
    in
    drain_headers ();
    let buf = Bytes.create !content_length in
    really_input stdin buf 0 !content_length;
    Yojson.Safe.from_string (Bytes.to_string buf)
  end

let write_message json =
  let body = Yojson.Safe.to_string json in
  Printf.printf "%s\n%!" body

(* ------------------------------------------------------------------ *)
(* JSON-RPC helpers                                                    *)
(* ------------------------------------------------------------------ *)

let response id result =
  `Assoc [ ("jsonrpc", `String "2.0"); ("id", id); ("result", result) ]

let error_response id code message =
  `Assoc
    [ ("jsonrpc", `String "2.0")
    ; ("id", id)
    ; ("error", `Assoc [ ("code", `Int code); ("message", `String message) ])
    ]

let text_content text =
  `Assoc [ ("type", `String "text"); ("text", `String text) ]

let tool_result text =
  `Assoc [ ("content", `List [ text_content text ]) ]

let tool_error text =
  `Assoc [ ("content", `List [ text_content text ]); ("isError", `Bool true) ]

(* ------------------------------------------------------------------ *)
(* Params: single declaration -> schema + decoding                     *)
(* ------------------------------------------------------------------ *)

type param_type = String | Int | Bool | StringArray

type param =
  { name : string
  ; desc : string
  ; typ : param_type
  ; required : bool
  }

let required_string name desc = { name; desc; typ = String; required = true }
let optional_string name desc = { name; desc; typ = String; required = false }
let required_int name desc = { name; desc; typ = Int; required = true }
let optional_int name desc = { name; desc; typ = Int; required = false }
let optional_bool name desc = { name; desc; typ = Bool; required = false }
let required_string_array name desc = { name; desc; typ = StringArray; required = true }

type args = (string * Yojson.Safe.t) list

let get_string (args : args) key =
  match List.assoc_opt key args with
  | Some (`String s) -> Ok s
  | Some _ -> Error (Printf.sprintf "Field '%s' must be a string" key)
  | None -> Error (Printf.sprintf "Missing required field '%s'" key)

let get_string_opt (args : args) key =
  match List.assoc_opt key args with
  | Some (`String s) -> Some s
  | _ -> None

let get_int (args : args) key =
  match List.assoc_opt key args with
  | Some (`Int i) -> Ok i
  | Some _ -> Error (Printf.sprintf "Field '%s' must be an integer" key)
  | None -> Error (Printf.sprintf "Missing required field '%s'" key)

let get_int_opt (args : args) key =
  match List.assoc_opt key args with
  | Some (`Int i) -> Some i
  | _ -> None

let get_bool_opt (args : args) key =
  match List.assoc_opt key args with
  | Some (`Bool b) -> Some b
  | _ -> None

let get_string_list (args : args) key =
  match List.assoc_opt key args with
  | Some (`List items) ->
    let rec collect acc = function
      | [] -> Ok (List.rev acc)
      | `String s :: rest -> collect (s :: acc) rest
      | _ :: _ -> Error (Printf.sprintf "Field '%s' must be an array of strings" key)
    in
    collect [] items
  | Some _ -> Error (Printf.sprintf "Field '%s' must be an array of strings" key)
  | None -> Error (Printf.sprintf "Missing required field '%s'" key)

let ( let* ) = Result.bind

(* ------------------------------------------------------------------ *)
(* Tool definition                                                     *)
(* ------------------------------------------------------------------ *)

type tool_def =
  { name : string
  ; description : string
  ; params : param list
  ; handler : args -> (string, string) result
  }

let param_to_prop p =
  match p.typ with
  | StringArray ->
    ( p.name
    , `Assoc
        [ ("type", `String "array")
        ; ("items", `Assoc [ ("type", `String "string") ])
        ; ("description", `String p.desc)
        ] )
  | _ ->
    let type_str = match p.typ with String -> "string" | Int -> "integer" | Bool -> "boolean" | StringArray -> assert false in
    (p.name, `Assoc [ ("type", `String type_str); ("description", `String p.desc) ])

let tool_to_json t =
  let props = List.map param_to_prop t.params in
  let required =
    List.filter_map
      (fun p -> if p.required then Some (`String p.name) else None)
      t.params
  in
  `Assoc
    [ ("name", `String t.name)
    ; ("description", `String t.description)
    ; ( "inputSchema"
      , `Assoc
          [ ("type", `String "object")
          ; ("properties", `Assoc props)
          ; ("required", `List required)
          ] )
    ]

(* ------------------------------------------------------------------ *)
(* Server configuration                                                *)
(* ------------------------------------------------------------------ *)

type config =
  { name : string
  ; version : string
  ; tools : tool_def list
  }

(* ------------------------------------------------------------------ *)
(* Main server loop                                                    *)
(* ------------------------------------------------------------------ *)

let dispatch cfg name args_json =
  let args = match args_json with `Assoc obj -> obj | _ -> [] in
  match List.find_opt (fun (t : tool_def) -> t.name = name) cfg.tools with
  | None -> tool_error (Printf.sprintf "Unknown tool: %s" name)
  | Some (t : tool_def) ->
    (match t.handler args with
     | Ok msg -> tool_result msg
     | Error e -> tool_error e)

let run config =
  set_binary_mode_in stdin true;
  set_binary_mode_out stdout true;
  Logs.info (fun m -> m "%s MCP server started" config.name);
  let tools_json = List.map tool_to_json config.tools in
  let running = ref true in
  while !running do
    (try
       let msg = read_message () in
       Logs.debug (fun m ->
           m "recv: %s" (Yojson.Safe.to_string msg));
       (match msg with
        | `Assoc fields ->
          let method_ =
            match List.assoc_opt "method" fields with
            | Some (`String m) -> m
            | _ -> ""
          in
          let id =
            match List.assoc_opt "id" fields with
            | Some v -> v
            | None -> `Null
          in
          let params =
            match List.assoc_opt "params" fields with
            | Some v -> v
            | None -> `Assoc []
          in
          let reply =
            match method_ with
            | "initialize" ->
              let result =
                `Assoc
                  [ ("protocolVersion", `String "2024-11-05")
                  ; ("capabilities", `Assoc [ ("tools", `Assoc []) ])
                  ; ( "serverInfo"
                    , `Assoc
                        [ ("name", `String config.name)
                        ; ("version", `String config.version)
                        ] )
                  ]
              in
              Some (response id result)
            | "notifications/initialized" -> None
            | "tools/list" ->
              Some (response id (`Assoc [ ("tools", `List tools_json) ]))
            | "tools/call" ->
              let obj = match params with `Assoc o -> o | _ -> [] in
              (match get_string obj "name" with
               | Error e -> Some (error_response id (-32602) e)
               | Ok name ->
                 let args =
                   match List.assoc_opt "arguments" obj with
                   | Some v -> v
                   | None -> `Assoc []
                 in
                 Some (response id (dispatch config name args)))
            | m when String.length m > 0 && m.[0] = '$' -> None
            | _ ->
              Some
                (error_response id (-32601)
                   (Printf.sprintf "Method not found: %s" method_))
          in
          (match reply with Some r -> write_message r | None -> ())
        | _ -> ())
     with
     | End_of_file ->
       Logs.info (fun m -> m "stdin closed (End_of_file), exiting");
       running := false
     | Yojson.Json_error msg ->
       Logs.err (fun m -> m "JSON parse error: %s" msg)
     | exn ->
       Logs.err (fun m -> m "Unhandled exception: %s" (Printexc.to_string exn)))
  done;
  Logs.info (fun m -> m "server loop ended")
