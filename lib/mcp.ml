(** Generic MCP server: JSON-RPC 2.0 over stdio with NDJSON framing. *)

(* ------------------------------------------------------------------ *)
(* I/O framing                                                         *)
(*                                                                     *)
(* Messages are written one JSON object per line (NDJSON), which is    *)
(* what the MCP stdio transport specifies. Content-Length-framed input *)
(* (LSP-style) is also accepted for leniency, but outgoing messages    *)
(* are always NDJSON, so a client speaking only Content-Length framing *)
(* will not get responses in the framing it expects.                  *)
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

let ( let* ) = Result.bind

(* ------------------------------------------------------------------ *)
(* Params: a GADT of argument shapes, from which both the JSON schema  *)
(* and the decoder are derived.                                        *)
(* ------------------------------------------------------------------ *)

type args = (string * Yojson.Safe.t) list

type _ typ =
  | String : string typ
  | Int : int typ
  | Bool : bool typ
  | Array : 'a typ -> 'a list typ
  | Option : 'a typ -> 'a option typ

type 'a param = { name : string; desc : string; typ : 'a typ }
type any_param = Any : 'a param -> any_param

let string_param ~name ~desc = { name; desc; typ = String }
let int_param ~name ~desc = { name; desc; typ = Int }
let bool_param ~name ~desc = { name; desc; typ = Bool }
let array_param ~name ~desc typ = { name; desc; typ = Array typ }
let optional (p : 'a param) : 'a option param =
  { name = p.name; desc = p.desc; typ = Option p.typ }

let rec decode_value : type a. a typ -> Yojson.Safe.t -> (a, string) result =
 fun typ json ->
  match typ, json with
  | String, `String s -> Ok s
  | String, _ -> Error "must be a string"
  | Int, `Int i -> Ok i
  | Int, _ -> Error "must be an integer"
  | Bool, `Bool b -> Ok b
  | Bool, _ -> Error "must be a boolean"
  | Array t, `List items ->
    let rec go i acc = function
      | [] -> Ok (List.rev acc)
      | x :: rest ->
        (match decode_value t x with
         | Ok v -> go (i + 1) (v :: acc) rest
         | Error e -> Error (Printf.sprintf "element %d %s" i e))
    in
    go 0 [] items
  | Array _, _ -> Error "must be an array"
  | Option t, json ->
    (match decode_value t json with
     | Ok v -> Ok (Some v)
     | Error e -> Error e)

let decode_field : type a. a typ -> args -> string -> (a, string) result =
 fun typ args name ->
  match typ with
  | Option t ->
    (match List.assoc_opt name args with
     | None -> Ok None
     | Some json ->
       (match decode_value t json with
        | Ok v -> Ok (Some v)
        | Error e -> Error (Printf.sprintf "Field '%s' %s" name e)))
  | _ ->
    (match List.assoc_opt name args with
     | None -> Error (Printf.sprintf "Missing required field '%s'" name)
     | Some json ->
       Result.map_error (Printf.sprintf "Field '%s' %s" name)
         (decode_value typ json))

let rec schema_of : type a. a typ -> string * (string * Yojson.Safe.t) list =
 fun typ ->
  match typ with
  | String -> "string", []
  | Int -> "integer", []
  | Bool -> "boolean", []
  | Array t ->
    let items_type, items_extra = schema_of t in
    ( "array"
    , [ ("items", `Assoc (("type", `String items_type) :: items_extra)) ] )
  | Option t -> schema_of t

let is_required : type a. a typ -> bool = function
  | Option _ -> false
  | Array _ | String | Int | Bool -> true

let param_to_prop (Any p) =
  let type_str, extra = schema_of p.typ in
  ( p.name
  , `Assoc (("type", `String type_str) :: ("description", `String p.desc) :: extra)
  )

(* ------------------------------------------------------------------ *)
(* Tool definition                                                     *)
(* ------------------------------------------------------------------ *)

type tool_def =
  { name : string
  ; description : string
  ; params : any_param list
  ; handler : args -> (string, string) result
  }

(* A builder threads a fixed handler type ['f] through, accumulating a
   list of params and a decoder that peels one argument off ['r] (the
   type still missing before reaching the final result) per [field]
   call. [tool] starts with zero params consumed (['r] = ['f]); [handle]
   supplies the handler once every param has been consumed (['r] =
   [(string, string) result]). *)
type ('f, 'r) builder =
  { b_name : string
  ; b_description : string
  ; b_params : any_param list
  ; decode : args -> 'f -> ('r, string) result
  }

let tool ~name ~description : ('f, 'f) builder =
  { b_name = name; b_description = description; b_params = []; decode = (fun _ h -> Ok h) }

let field (p : 'a param) (b : ('f, 'a -> 'r) builder) : ('f, 'r) builder =
  { b with
    b_params = Any p :: b.b_params
  ; decode =
      (fun args h ->
        match b.decode args h with
        | Error e -> Error e
        | Ok partial ->
          (match decode_field p.typ args p.name with
           | Ok v -> Ok (partial v)
           | Error e -> Error e))
  }

let handle (h : 'f) (b : ('f, (string, string) result) builder) : tool_def =
  { name = b.b_name
  ; description = b.b_description
  ; params = List.rev b.b_params
  ; handler =
      (fun args ->
        (* [decode] itself succeeds/fails at parsing args; on success it
           carries the handler's own (string, string) result, which must
           be unwrapped rather than nested. *)
        match b.decode args h with
        | Ok result -> result
        | Error e -> Error e)
  }

(* A zero-param tool has no [field] to defer evaluation past construction
   time, so [handle]'s ['f] would collapse to the result itself and [h]
   would run once at startup instead of per request. Take an explicit
   thunk instead. *)
let handle0 ~name ~description (h : unit -> (string, string) result) : tool_def =
  { name; description; params = []; handler = (fun _args -> h ()) }

let tool_to_json t =
  let props = List.map param_to_prop t.params in
  let required =
    List.filter_map
      (fun (Any p) -> if is_required p.typ then Some (`String p.name) else None)
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
              (match List.assoc_opt "name" obj with
               | Some (`String name) ->
                 let args =
                   match List.assoc_opt "arguments" obj with
                   | Some v -> v
                   | None -> `Assoc []
                 in
                 Some (response id (dispatch config name args))
               | _ ->
                 Some (error_response id (-32602) "Missing required field 'name'"))
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
