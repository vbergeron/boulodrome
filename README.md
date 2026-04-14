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

### `rocq_try_tactics`

Tries each tactic independently on the current proof state **without modifying the session**. Every tactic in the list is run from the same starting state, so you can compare alternatives even if some fail. Use `rocq_run_tactics` to commit the chosen tactic.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to try tactics in |
| `tac_list` | string[] | yes | Tactics to try, e.g. `["induction n.", "simpl.", "auto."]` |
| `verbose` | bool | no | If true, show the goal state after each tactic (default: false) |

---

### `rocq_goals`

Returns the current goal state for a session.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to inspect |

Returns focused goals, hypotheses, and any unfocused or shelved goals.

---

### `rocq_premises`

Returns up to 20 premises (lemmas and definitions) available in the current proof context.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | yes | Session to inspect |

Useful for discovering what lemmas are in scope before deciding which tactic to apply.

---

### `rocq_file_toc`

Returns the table of contents of a `.v` file: all definitions and theorems with their kind, line number, and structural details.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | yes | Absolute path to the `.v` file |

Each entry shows the declaration kind, line number, and full statement. For example:

```
- [Inductive] nat { O, S } (line 5)
    Inductive nat : Set :=  O : nat | S : nat -> nat.
- [Theorem] plus_comm (line 12)
    Theorem plus_comm : forall n m : nat, n + m = m + n.
- [Definition] double (line 20)
    Definition double := fun n : nat => n + n.
- [Record] point { x, y } (line 25)
    Record point : Set := mk_point { x : nat; y : nat }.
```

Use this to discover what theorems are available before starting a session.

---

### `rocq_diagnostics`

Returns all diagnostic messages (errors, warnings, information, hints) for a `.v` file. Use the optional `severity` parameter to filter to a single level.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | yes | Absolute path to the `.v` file |
| `severity` | string | no | Filter by severity: `"error"`, `"warning"`, `"information"`, or `"hint"`. If omitted, all diagnostics are returned. |

Each diagnostic is formatted as `l<line>c<col>-l<line>c<col>, <severity>: <message>`.

---

### `rocq_search`

Searches for theorems, definitions, and other objects using Rocq's `Search`, `SearchPattern`, or `SearchRewrite` commands. The `query` is passed verbatim as the argument to the chosen command.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | no | Session whose context to search in (provide this or `file_path`) |
| `file_path` | string | no | Absolute path to a `.v` file (alternative to `session_id`) |
| `query` | string | yes | Rocq search expression, passed verbatim (see syntax below) |
| `kind` | string | yes | `"search"`, `"search_pattern"`, or `"search_rewrite"` |
| `max_results` | int | no | Maximum number of results (default: 30) |

Provide either `session_id` (to search in a proof context) or `file_path` (to search from a file's root context). `session_id` takes precedence.

#### Query syntax (for `kind="search"`)

- **Pattern**: `(_ + _ = _ + _)` — type pattern with holes `_` or named metavariables `?n`
- **Name substring**: `"assoc"` — quoted string, matches object names containing the substring
- **Notation**: `"+"` — quoted, finds objects whose type uses this notation
- **Qualifiers**: `hyp:`, `concl:`, `head:`, `headhyp:`, `headconcl:` before a pattern or string
- **Negation**: `- query` — exclude matching objects
- **Kind filter**: `is:Lemma`, `is:Definition`, `is:Instance`, `is:Fixpoint`, etc.
- **Scope**: `... inside ModuleName` or `... outside ModuleName`
- **Disjunction**: `[ query1 | query2 ]`

#### Examples

| Query | Finds |
|-------|-------|
| `plus_comm` | Objects matching `plus_comm` |
| `(_ + _ = _ + _)` | Commutativity lemmas |
| `"assoc"` | All names containing "assoc" |
| `concl:(nat -> bool)` | Functions returning `bool` in the conclusion |
| `is:Lemma (_ + _)` | Lemmas about addition |
| `(_ * _) -"trivial"` | Multiplication results, excluding names with "trivial" |

For `kind="search_pattern"`: matches the conclusion shape only (not subterms).
For `kind="search_rewrite"`: finds rewrite lemmas where one side of an equality matches the pattern.

---

### `rocq_inspect`

Inspect a Rocq term or object using `Check`, `Print`, `About`, or `Locate`. Returns type signatures, full definitions, documentation, or location information.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `session_id` | string | no | Session whose context to inspect in (provide this or `file_path`) |
| `file_path` | string | no | Absolute path to a `.v` file (alternative to `session_id`) |
| `command` | string | yes | `"check"`, `"print"`, `"about"`, or `"locate"` |
| `term` | string | yes | The term, definition, or identifier to inspect |

Provide either `session_id` (to inspect in a proof context) or `file_path` (to inspect from a file's root context). `session_id` takes precedence.

#### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `check` | Show the type of a term | `Nat.add` → `Nat.add : nat -> nat -> nat` |
| `print` | Show the full definition of an object | `Nat.add` → recursive definition body |
| `about` | Show info including implicit arguments and scopes | `Nat.add` → argument details, notations |
| `locate` | Show the full qualified name and module | `Nat.add` → `Coq.Init.Nat.add` |

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

Boulodrome is configured as an MCP server in your editor or agent. A ready-made rule file is provided in [`rules/boulodrome-mcp.mdc`](rules/boulodrome-mcp.mdc). Copy it into your Rocq project's `.cursor/rules/` directory (or the equivalent rules directory for your editor):

```bash
cp rules/boulodrome-mcp.mdc /path/to/your/rocq/project/.cursor/rules/
```

The MCP server itself is registered in your editor's MCP settings:

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

---

## License

Apache-2.0 — see [LICENSE](LICENSE).

## Changelog

See [CHANGES.md](CHANGES.md) for the full release history.
