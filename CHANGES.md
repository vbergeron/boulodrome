# Changelog

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
