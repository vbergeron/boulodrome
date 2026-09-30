# Test plan

Boulodrome currently has a single test: the `l<line>c<col>` position parser
in `test/test_boulodrome.ml`. This document plans a test suite in three
layers, from cheapest to most expensive, and the order to build it in.

| Layer | What it checks | Starts Rocq? | Tooling | Speed |
|---|---|---|---|---|
| **1. Pure unit** | param decoding, formatting, session history, parsers | no | Alcotest | < 1 s |
| **2. Rocq integration** | each tool's `run` called directly on fixture `.v` files | yes, in-process | Alcotest | seconds |
| **3. End-to-end MCP** | the `boulodrome` binary over stdio: JSON-RPC, schemas, errors | yes, via the binary | dune cram | seconds |

**Tooling.** Add `alcotest` as a `{with-test}` dependency for layers 1 and 2
(named test cases, readable failures). Layer 3 uses dune's built-in cram
tests, with no extra dependency. CI already runs `dune test`, so the
workflow needs no change.

---

## Layer 1: pure unit tests (no Rocq)

### `Mcp`: the param GADT, builder and generic server

The highest-value module to cover. It has already regressed once
(302f457: `handle` nested the handler's result instead of flattening it).

- `decode_value` / `decode_field`: every GADT case (`String`, `Int`, `Bool`,
  `Array`, `Option`, `Convert`), a missing required field, a wrong type, and
  the exact error message (e.g. `Field 'tac_list' element 2 must be a string`).
- `Convert`: a conversion that succeeds, one that fails, and
  `Option (Convert _)` with the field absent or present.
- `tool_to_json`: `required` lists exactly the non-optional params
  (`Option` and `Convert (Option _)` excluded), in declaration order;
  `Array` params carry `items`.
- `handle` / `handle0`: the handler's own `Error` is returned flat, not
  nested; a `handle0` handler runs on every request, not once at startup.
- `dispatch`: an unknown tool yields `isError: true`; a decoding error is
  reported as a tool error.
- Framing: NDJSON and `Content-Length` input are both accepted.
  **Prerequisite refactor:** `read_message` reads `stdin` directly; make it
  take an `in_channel` so tests can feed it a string.

### `Session`: permanently indexed proof states

- Sequences of `create` / `set` / `undo n` / `undo_to id`: assigned ids,
  `undo` clamped at the root (`NoUndo` when there is nothing to undo),
  jumping to a state on another branch, `tactics` returning the current
  lineage only (not the whole history), `remove` then `list`.
- **Prerequisite refactor:** the state is an opaque `Agent.State.t` that
  cannot be built without Rocq. Making the table generic over the state
  type (a functor, or a `'st` type parameter) lets all of this logic be
  tested with plain integers. This is probably the biggest win of layer 1.

### Other pure functions (testable as-is)

- `Dune_loadpath`: `has_theory_stanza` and `extract_name` on varied
  contents (`rocq.theory`, `coq.theory`, end of file, false positive inside
  a comment); `discover` on a temporary tree, checking `_build/` and
  `.git/` are skipped.
- `Verify`: `axioms_of_report` (closed context, one axiom, several) and
  `is_whitelisted`.
- `Search`: `kind_of_string`, `is_wrapped`. `Diagnostics`:
  `severity_of_string` / `severity_to_string` round-trip.
- `Tools_helpers.contains`, and `Start_proof.parse_position` (existing test,
  to migrate to Alcotest).
- `Goal.format` / `Goal.are_complete` on hand-built reified goals, including
  the 0.2.0 regression: a proof reported complete while unfocused goals
  remained.

---

## Layer 2: Rocq integration

### Harness

A `setup ()` boots Rocq once (`Coq_init.init_agent`) on `test/fixtures/`;
each test then calls the tools' `run` functions directly.

- Fixtures use **Corelib only**, so the suite does not depend on
  `rocq-stdlib` (otherwise add it as a `{with-test}` dependency).
- Declare `(data_only_dirs fixtures)` in `test/dune`, so dune does not try
  to build the fixtures' `.v` files as part of the project.

### Fixtures

- `Basic.v`: a provable theorem needing induction, with unfocused goals.
- `Broken.v`: a proof that breaks at a known line, to pin down
  line/column positions.
- `Axioms.v`: an `Axiom`, an `Admitted` lemma, and an axiom-free lemma.
- `Records.v`: a record and an inductive type, for the table of contents.

### Scenarios per tool

- **`start_proof`**
  - By name: state 0, expected goals.
  - Unknown name: `Theorem_not_found` plus the document's errors.
  - **By position** (merged in #23, not yet covered by an automated test):
    the error position in `Broken.v` gives the state just before the failing
    tactic; a point between two sentences gives the state after the
    preceding one; a point after `Qed.` gives "No proof is open"; the theorem
    name is recovered from the enclosing proof.
- **`run_tactics`**: stops at the first failure without advancing past it;
  `[state N]` ids are reported; `verbose` shows goals after each tactic.
- **`try_tactics`**: the session state is unchanged afterwards.
- **`undo`**: by step count, by id, and switching between branches.
- **`proof_script`**: a `;` chain and bullets are returned verbatim;
  splicing the script back into the file compiles (checked with
  `diagnostics`).
- **`search`**: by name, by pattern, and the auto-wrap retry for a query
  with a top-level infix operator (`_ + _` without parentheses).
- **`inspect`**: `check`, `print`, `about`, `locate`, `assumptions`.
- **`verify`**: a clean file passes; `Admitted` and `Axiom` are flagged;
  `allowed_axioms` accepts an axiom; a file with errors is not verified; an
  unknown `theorem_name` is an error.
- **`file_toc`**: 0.6.0 regression, record fields and constructors are not
  listed as separate top-level entries.
- **`diagnostics`**: the `lXcY` format and severity filtering.
- **File reload** (0.2.0 regression, environment desync): edit a `.v`
  between two calls and check the second call sees the change.

---

## Layer 3: end-to-end MCP (cram)

A `test/e2e.t/` cram test runs `boulodrome fixtures/` and pipes NDJSON
lines to it:

- `initialize`, then `tools/list`: **snapshot of all 15 tool schemas**, so
  any API change shows up in the diff.
- A full scenario: `tools/call` `rocq_start_proof`, then
  `rocq_run_tactics`, then `rocq_proof_script`.
- Protocol errors: unknown method (-32601), missing `name` (-32602), a
  missing required field (`isError`), a notification gets no reply, invalid
  JSON does not kill the loop.
- Closing stdin shuts the server down cleanly.

Filter volatile output (evar numbers, absolute paths) with `sed` in the
cram script before comparing, or snapshots will break on every Rocq
release.

---

## Order of work

- [ ] **1. Layer 1 on `Mcp`, and migrate the existing test to Alcotest.**
      Highest value, no risk.
- [ ] **2. Make `Session` generic over its state and test it.** Small
      refactor, critical logic.
- [ ] **3. Layer 2 harness and fixtures**, starting with `start_proof` by
      position, `undo` and `proof_script`.
- [ ] **4. Rest of layer 2**: `verify`, `file_toc`, `search`, regressions.
- [ ] **5. Layer 3 cram tests**, including the schema snapshot.

**Risk to watch:** the first CI run of layer 2 is what validates that Rocq
boots inside a test executable (coqlib discovery, plugin loading). Expect
that step to need a round of iteration.
