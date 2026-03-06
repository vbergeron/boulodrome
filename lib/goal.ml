open Coq.Goals

let count_stack_goals stack =
  List.fold_left
    (fun acc (l, r) -> acc + List.length l + List.length r)
    0 stack

let are_complete (goals_opt : (string, string) reified option) =
  match goals_opt with
  | None -> true
  | Some goals ->
    goals.goals = []
    && count_stack_goals goals.stack = 0
    && goals.shelf = []
    && goals.given_up = []

let format_info (info : Reified_goal.info) =
  let name = match info.name with
    | Some id -> Printf.sprintf " (%s)" (Names.Id.to_string id)
    | None -> ""
  in
  Printf.sprintf "?%d%s" (Evar.repr info.evar) name

let format_hyp buf (h : string Reified_goal.hyp) =
  let names = String.concat ", " h.names in
  match h.def with
  | None ->
    Buffer.add_string buf (Printf.sprintf "  %s : %s\n" names h.ty)
  | Some d ->
    Buffer.add_string buf (Printf.sprintf "  %s := %s : %s\n" names d h.ty)

let format_goal_brief buf (g : string Reified_goal.t) =
  Buffer.add_string buf
    (Printf.sprintf "  %s : %s\n" (format_info g.info) g.ty)

let format_goal buf ~idx ~total (g : string Reified_goal.t) =
  Buffer.add_string buf
    (Printf.sprintf "Goal %d/%d (evar %s):\n" (idx + 1) total (format_info g.info));
  List.iter (format_hyp buf) g.hyps;
  Buffer.add_string buf "  ⊢ ";
  Buffer.add_string buf g.ty;
  Buffer.add_char buf '\n'

let format_bullet buf = function
  | Some b -> Buffer.add_string buf (Printf.sprintf "Bullet: %s\n" b)
  | None -> ()

let format_focused buf goals =
  let n = List.length goals in
  List.iteri (fun idx g -> format_goal buf ~idx ~total:n g) goals

let format_unfocused buf stack =
  let n = count_stack_goals stack in
  if n > 0 then begin
    Buffer.add_string buf (Printf.sprintf "Unfocused (%d):\n" n);
    List.iter
      (fun (before, after) ->
        List.iter (format_goal_brief buf) (before @ after))
      stack
  end

let format_shelved buf shelf =
  let n = List.length shelf in
  if n > 0 then begin
    Buffer.add_string buf (Printf.sprintf "Shelved (%d):\n" n);
    List.iter (format_goal_brief buf) shelf
  end

let format_given_up buf given_up =
  let n = List.length given_up in
  if n > 0 then begin
    Buffer.add_string buf (Printf.sprintf "Given up (%d):\n" n);
    List.iter (format_goal_brief buf) given_up
  end

let format_header buf ~n_focused ~n_unfocused ~n_total =
  if n_focused > 0 then
    Buffer.add_string buf
      (Printf.sprintf "[Goal 1 of %d | %d unfocused]\n" n_total n_unfocused)
  else
    Buffer.add_string buf
      (Printf.sprintf "[%d unfocused goal(s) remaining, none currently focused]\n"
         n_unfocused)

let format (goals_opt : (string, string) reified option) =
  match goals_opt with
  | None -> "No goals — proof may already be complete."
  | Some goals ->
    let n_focused = List.length goals.goals in
    let n_unfocused = count_stack_goals goals.stack in
    let n_total =
      n_focused + n_unfocused
      + List.length goals.shelf
      + List.length goals.given_up
    in
    if n_total = 0 then
      "No remaining goals — proof complete!"
    else begin
      let buf = Buffer.create 256 in
      format_header buf ~n_focused ~n_unfocused ~n_total;
      format_bullet buf goals.bullet;
      format_focused buf goals.goals;
      format_unfocused buf goals.stack;
      format_shelved buf goals.shelf;
      format_given_up buf goals.given_up;
      Buffer.contents buf
    end
