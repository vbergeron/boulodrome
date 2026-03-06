let has_theory_stanza content =
  let rec check i =
    if i >= String.length content - 11 then false
    else
      let sub11 = String.sub content i 11 in
      let sub12 = if i + 12 <= String.length content
        then String.sub content i 12 else "" in
      if sub11 = "coq.theory " || sub11 = "coq.theory\n"
         || sub12 = "rocq.theory " || sub12 = "rocq.theory\n"
      then true
      else check (i + 1)
  in
  check 0

let extract_name content =
  let needle = "(name " in
  let nlen = String.length needle in
  let rec find i =
    if i + nlen >= String.length content then None
    else if String.sub content i nlen = needle then
      let start = i + nlen in
      let rec end_pos j =
        if j >= String.length content then None
        else if content.[j] = ')' || content.[j] = ' ' || content.[j] = '\n'
        then Some (String.sub content start (j - start))
        else end_pos (j + 1)
      in
      end_pos start
    else find (i + 1)
  in
  find 0

let read_file path =
  In_channel.with_open_text path In_channel.input_all

let find_ws_root start =
  let rec go dir =
    let dp = Filename.concat dir "dune-project" in
    if Sys.file_exists dp then Some dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then None
      else go parent
  in
  go start

let discover ~root =
  let ws_root = match find_ws_root root with Some r -> r | None -> root in
  let results = ref [] in
  let rec walk dir =
    let entries = try Sys.readdir dir with Sys_error _ -> [||] in
    Array.iter
      (fun entry ->
        let path = Filename.concat dir entry in
        if entry = "_build" || entry = ".git" then ()
        else if Sys.is_directory path then walk path
        else if entry = "dune" then begin
          let content = read_file path in
          if has_theory_stanza content then
            match extract_name content with
            | Some name ->
              let theory_dir = Filename.dirname path in
              let rel =
                let wlen = String.length ws_root in
                if String.length theory_dir > wlen
                then String.sub theory_dir (wlen + 1)
                       (String.length theory_dir - wlen - 1)
                else "."
              in
              let unix_path =
                Filename.concat ws_root
                  (Filename.concat "_build"
                     (Filename.concat "default" rel))
              in
              let coq_path = Libnames.dirpath_of_string name in
              results :=
                { Loadpath.unix_path
                ; coq_path
                ; implicit = false
                ; recursive = true
                ; installed = false
                }
                :: !results
            | None -> ()
        end)
      entries
  in
  walk ws_root;
  !results
