---
name: implement-pizza-service
description: Guide a real implementation of the pizza-pattern contracts, from interview to verified definition of done. Use when asked to implement the pizza service, build the API for real, or take the contracts to production.
---

# Implement the pizza service

You are implementing the pizza-pattern contracts for real. The contracts are
the authority; this skill is only the process for getting from them to a
verified implementation.

## Phase 0 — locate the contracts

This skill may be running inside the pizza-pattern repo or, installed as a
plugin, in any project. Never work from an embedded or remembered copy of the
contracts:

- If the current project is a pizza-pattern checkout (a `specs/openapi.yaml`
  titled "Pizza Service API"), use it.
- Otherwise clone the contract repo at this skill release's pinned ref and
  resolve every path below against the clone:

  ```sh
  git clone --depth 1 --branch main https://github.com/hungovercoders/pizza-pattern
  ```

  Pinned ref: `main` — until the contracts are tagged; plugin releases then
  bump this to a tag so "which contract version does this skill implement" is
  explicit.

Do not restate or paraphrase contract rules from memory — read them from the
files each time:

- `specs/openapi.yaml`, `specs/asyncapi.yaml` — the interface
- `specs/features/*.feature` — the cross-interaction rules (normative)
- `docs/implementing.md` — the definition of done this skill exists to reach
- `docs/decisions.md` — why the contract is shaped the way it is

## Ground rules

- Never edit the specs or features to make an implementation pass. A red suite
  is a finding about the implementation. Contract changes are separate work,
  gated by `task check:compat` (breaking changes need a version bump).
- Internals — queue, storage, framework — are free choices, and they stay out
  of the implementation's public documentation for the same reason they are
  absent from the contracts (see `docs/decisions.md`).
- Report verification results honestly: a failing suite is reported as
  failing, with output, not routed around.

## Phase 1 — interview

Ask before writing any code (one round of questions where possible):

1. **Language and framework** for the service.
2. **Where the implementation lives** — a new repository (recommended; this
   repo stays contracts-only) or a path the user names.
3. **Hosting / runtime target** — affects scaffolding and CI, nothing
   contractual.
4. **Event transport** — the contract deliberately leaves it open (see the
   "WebSocket is the mock transport" decision). The choice must be one the
   Microcks async test runner can point at, because it becomes the scheme of
   the `WS_ENDPOINT` override in verification (e.g. `ws://`, `kafka://`,
   `mqtt://`, `amqp://`).
5. **Storage** — for pizza state/history and for idempotency-key records.
6. **Constraints** — CI system, org package registries, observability stack,
   anything third-party the implementation must fit into.

Do **not** interview about anything the contract already decides: endpoints,
status codes, states and transitions, the CloudEvents envelope, idempotency
semantics, read-your-writes. If the user wants one of those changed, stop —
that is a contract change in this repo first, not an implementation choice.

## Phase 2 — build

- Read the specs and features before scaffolding; generate or hand-write from
  the contract files, never from memory of them.
- Reference this repo from the implementation by pinned clone (tag or commit),
  the same way `docs/quickstart.md` pins it for consumer CI — the contract
  files stay single-source.
- Bind `specs/features/*.feature` with a Cucumber implementation for the
  chosen language. Bind the files from the pinned clone; do not copy or
  paraphrase them into the implementation repo.

## Phase 3 — verify (the definition of done)

Loop until all three are green, then confirm against the checklist in
`docs/implementing.md`:

1. **Contract tests** — from this repo, against the running implementation
   (endpoints must be reachable from the Microcks container):

   ```sh
   task mocks:contract REST_ENDPOINT=<http url> WS_ENDPOINT=<transport url>
   ```

2. **The bound feature suite** against the running implementation.

3. **Schema fuzz** for declared-but-unexampled paths:

   ```sh
   uvx schemathesis run specs/openapi.yaml --url <http url>
   ```

## Phase 4 — wire the implementation's CI

Recreate the loop in the implementation's pipeline using the pinned clone
(same shape as the consumer recipe in `docs/quickstart.md`): start the stack,
start the implementation, run the three checks above, tear down. The
implementation's CI then enforces the same definition of done as this repo
declares — one definition of "correct", no drift.
