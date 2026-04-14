(lang dune 3.21)

(name boulodrome)

(using rocq 0.11)

(generate_opam_files true)

(license Apache-2.0)

(authors "Valentin Bergeron <dev.vbergeron@gmail.com>")

(maintainers "Valentin Bergeron <dev.vbergeron@gmail.com>")

(source
 (github vbergeron/boulodrome))

(package
 (name boulodrome)
 (synopsis "MCP server for Rocq/Coq proof assistance via Petanque")
 (description
  "Boulodrome gives LLMs interactive access to the Rocq proof assistant \
   through the Model Context Protocol (MCP). It exposes tools for starting \
   proof sessions, running tactics, inspecting goals, searching the library, \
   and undoing steps, turning theorem proving into a tool-calling loop.")
 (depends
  (ocaml (>= 5.2.1))
  yojson
  logs
  (coq-lsp (>= 0.2.5))))
