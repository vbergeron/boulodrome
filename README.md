# Boulodrome

An [MCP](https://modelcontextprotocol.io/) server that gives LLMs interactive access to the [Rocq](https://rocq-prover.org/) proof assistant via the [Petanque](https://github.com/ejgallego/coq-lsp/tree/main/petanque) API. It lets an AI assistant start proof sessions, run tactics, inspect goals, search the library, and undo steps — turning theorem proving into a tool-calling loop.

Communication happens over stdio using JSON-RPC 2.0 with `Content-Length` framing, which is standard MCP transport. Logs are written to `/tmp/boulodrome.log`.

---

## Tools

### `rocq_start_proof`

Opens a proof session for a named theorem inside a `.v` file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | yes | Absolute path to the `.v` file |
| `theorem_name` | string | yes | Name of the theorem to prove |
| `session_id` | string | yes | Unique identifier you choose for this session |
| `pre_commands` | string | no | Rocq commands to execute before starting (e.g. `From Stdlib Require Import Arith.`) |

Returns the initial goal state. Automatically discovers and loads Rocq loadpaths from `dune` files in the workspace.

---

### `rocq_run_tactics`

Executes a list of tactics on the current proof state. Stops at the first failure.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to run tactics in |
| `tac_list` | string[] | yes | Tactics to run, e.g. `["induction n.", "simpl.", "auto."]` |
| `verbose` | bool | no | If true, show the goal state after each tactic (default: false) |

Returns the output of each tactic. If a tactic fails, the proof state is not advanced past the failure and the error message is included in the response.

---

### `rocq_get_goals`

Returns the current goal state for a session.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to inspect |

Returns focused goals, hypotheses, and any unfocused or shelved goals.

---

### `rocq_get_premises`

Returns up to 20 premises (lemmas and definitions) available in the current proof context.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to inspect |

Useful for discovering what lemmas are in scope before deciding which tactic to apply.

---

### `rocq_get_file_toc`

Returns the table of contents of a `.v` file: all definitions and theorems with their positions.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | yes | Absolute path to the `.v` file |

Use this to discover what theorems are available before starting a session.

---

### `rocq_search`

Searches for theorems, definitions, and other objects matching a query in the current proof context.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session whose context to search in |
| `query` | string | yes | Name pattern or type expression, e.g. `plus_comm` or `nat -> nat` |

Returns up to 50 results. Requires an active session because the search scope depends on what is loaded.

---

### `rocq_undo`

Undoes the last N tactic steps, restoring an earlier proof state.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to undo in |
| `steps` | int | no | Number of steps to undo (default: 1) |

Returns the number of steps actually undone and the goal state after undoing.

---

### `rocq_end_session`

Closes a proof session and frees its state.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to close |

---

## Installation

Boulodrome is not published to opam, so it must be installed from source. It depends on `coq-lsp` (>= 0.2.5), which must be available in your opam switch.

```bash
git clone https://github.com/vbergeron/boulodrome
cd boulodrome
opam install . --deps-only
dune build
dune install
```

After `dune install`, the `boulodrome` binary is available in your opam switch's bin directory (`$(opam var bin)/boulodrome`).

### Requirements

- OCaml >= 5.2.1
- dune >= 3.21
- coq-lsp >= 0.2.5 (provides Petanque and Fleche)
- yojson, logs

---

## Usage from Rocq projects

Run `boulodrome` from the root of your Rocq project (or pass the root as an argument). It will walk the directory tree looking for `dune` files containing `(rocq.theory ...)` or `(coq.theory ...)` stanzas and add the corresponding loadpaths automatically.

```bash
# From within the project root:
boulodrome

# Or explicitly:
boulodrome /path/to/your/rocq/project
```

The MCP client (your IDE or agent) connects over stdio. File paths passed to tools must be absolute.

---

## Cursor / Claude configuration

Boulodrome is configured as an MCP server in your editor or agent. Below is an example rule file to drop into your Rocq project.

### Example `boulodrome-mcp.mdc`

```markdown
---
description: Rules for using boulodrome to assist with Rocq proofs
globs: ["**/*.v"]
alwaysApply: false
---

# Rocq proof assistant via boulodrome

You have access to the boulodrome MCP server, which lets you interact with the
Rocq proof assistant directly. Use these tools when the user asks you to prove
theorems or debug proofs in `.v` files.

## Workflow

1. Use `rocq_get_file_toc` to list theorems in a file before starting.
2. Use `rocq_start_proof` with a unique `session_id` to open a proof session.
3. Inspect the initial goal with `rocq_get_goals` or by reading the output of
   `rocq_start_proof`.
4. Use `rocq_search` or `rocq_get_premises` to find relevant lemmas.
5. Run tactics with `rocq_run_tactics`. Use `verbose: true` when you are
   uncertain about intermediate states.
6. Use `rocq_undo` to backtrack if a tactic sequence leads to a dead end.
7. Close the session with `rocq_end_session` when the proof is complete or
   abandoned.

## Guidelines

- Choose `session_id` values that are descriptive and unique, e.g.
  `"plus_comm_attempt_1"`.
- Prefer small `tac_list` batches (2–4 tactics) so failures are easy to
  pinpoint.
- After `rocq_undo`, re-read the goals before trying a new approach.
- If `rocq_start_proof` fails with a document error, check that `file_path`
  is absolute and that the file compiles in isolation.
- `rocq_search` needs an active session; open one before searching.
```

Save this file as `boulodrome-mcp.mdc` in `.cursor/rules/` (for Cursor) or the equivalent rules directory for your editor. The MCP server itself is registered in your editor's MCP settings:

**Cursor** (`~/.cursor/mcp.json` or the project-level `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "boulodrome": {
      "command": "boulodrome",
      "args": ["/path/to/your/rocq/project"]
    }
  }
}
```

**Claude Code** (`.mcp.json` in the project root):

```json
{
  "mcpServers": {
    "boulodrome": {
      "command": "boulodrome",
      "args": ["."]
    }
  }
}
```
