# Changelog

## Unreleased

- Add `rocq_proof_script` tool to retrieve the exact sequence of tactics committed in a session, verbatim and in order, so a proof can be spliced back into the source file without hand-transcribing it from the conversation (which risks breaking `;`-chained tactics that apply across multiple goals)
- Add `"assumptions"` command to `rocq_inspect` (`Print Assumptions`), to check whether a proof depends on any axioms or admitted lemmas without leaving the MCP
- Fix `rocq_file_toc` listing record fields (and inductive constructors) as separate top-level entries, each duplicating the full parent statement; only the statement's own top-level name is now listed, with fields/constructors still summarised in `{ ... }`
- Add `rocq_list_sessions` tool to enumerate currently open proof sessions with their file path, theorem name, and proof status
- Fix `rocq_search` rejecting patterns whose top level uses an infix operator (e.g. `{n < m} + {n = m} + {m < n}`) by automatically retrying the query wrapped in parentheses

## 0.5.0 (2026-04-14)

- Add `rocq_inspect` tool for inspecting terms with `Check`, `Print`, `About`, and `Locate`
- Add `rocq_diagnostics` tool for retrieving file diagnostics with optional severity filtering
- Rename `rocq_get_file_toc` to `rocq_file_toc`, `rocq_get_goals` to `rocq_goals`, `rocq_get_premises` to `rocq_premises`
- Enhance `rocq_file_toc` output with declaration kind, line numbers, children (record fields, constructors), and full statement text

## 0.4.1 (2026-04-14)

- Update README with `rocq_try_tactics` documentation and fix `rocq_search` `kind` parameter (required, not optional)

## 0.4.0 (2026-03-19)

- Add `rocq_try_tactics` tool for speculative tactic exploration

## 0.3.0 (2026-03-10)

- Enhance `rocq_search` with search kinds, file-based context, and detailed query documentation

## 0.2.0 (2026-03-06)

- Merge `run_tactic` and `run_tactics` into a single tool with a `verbose` option
- Accept `tac_list` as an array
- Refactor tools into per-file modules
- Fix environment desync by bumping Fleche file cache on each `build_doc`
- Fix false "proof complete" result by accounting for unfocused goals in the goal stack
- Fix `undo` to clamp steps to available history instead of erroring

## 0.1.0 (2026-03-06)

- Initial release: MCP server for Rocq/Coq proof assistance via Petanque
