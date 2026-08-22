# Implementing the contract

This page defines what **done** means for an implementation of these
contracts. It deliberately says nothing about *how* to build one — queue,
storage, language and framework are all internal concerns and out of scope,
exactly as they are in the contracts.

An implementation is conformant when all three hold:

## 1. The Microcks contract tests pass against its endpoints

The same runners that validate the mocks in `task ci` validate a real service —
only the endpoint under test changes:

```sh
task mocks:contract \
  REST_ENDPOINT=https://your-service.example.com \
  WS_ENDPOINT=wss://your-service.example.com/pizza/lifecycle
```

`OPEN_API_SCHEMA` replays every exampled HTTP exchange from
[`specs/openapi.yaml`](specs/openapi.yaml) and validates the responses;
`ASYNC_API_SCHEMA` validates observed events against
[`specs/asyncapi.yaml`](specs/asyncapi.yaml). The run fails on any
non-conformant exchange — and on a green result over zero exchanges. The
endpoints must be reachable from the Microcks container (it executes the test,
not your shell).

One caveat carries over from the mocks: the `notFound` GET parameter example
(`99999999-…`) and the `invalid` POST example expect a 404 and a 400 — a real
implementation satisfies these naturally, since those fixtures describe a pizza
that genuinely does not exist and a command that genuinely fails validation.

The runners validate only *exampled* exchanges. Declared-but-unexampled paths —
more than 8 `toppings`, unknown fields against `additionalProperties: false`,
malformed JSON, the 409 on Idempotency-Key reuse — are never exercised by them.
Cover those with schema-driven fuzzing (e.g.
[Schemathesis](https://schemathesis.readthedocs.io/) fed `specs/openapi.yaml`)
against your endpoints as part of your own suite — the contract file is the
input, so there is still one source of truth.

## 2. The behaviour features pass, bound against it

The [behaviour spec](behaviour.md) states the rules the schema runners cannot
check: idempotent replay, legal transitions, cancellation semantics,
event/status consistency. Bind the `.feature` files in
`specs/features/` with real steps (any Cucumber
implementation) driving the HTTP endpoints and consuming the event channel,
and keep them green. The features are the acceptance suite; do not fork or
paraphrase them into a separate test plan.

## 3. It relies on nothing beyond `specs/`

Anything else observable in the mocks — the fixture ids, the frozen
timestamps, the 30-second ambient event cadence, WebSocket as the event
transport — is fixture coincidence or mock plumbing, not contract. If a
behaviour you depend on is not in `specs/` (contracts or features), it is not
promised.

## Agent-assisted implementation

This definition of done also ships as an executable process for coding
agents: the `implement-pizza-service` skill at
`skills/implement-pizza-service/SKILL.md`. Open this repo in Claude Code and
ask it to implement the service — or install it from the marketplace to use
it from any project:

```text
/plugin marketplace add hungovercoders/pizza-pattern
/plugin install pizza-pattern@hungovercoders
```

The skill interviews for the free choices (language, hosting, event
transport, storage), refuses to re-litigate anything the contract already
decides, and loops the checks above until green. It contains process only;
every rule it enforces is read from the specs, features and this page, so
there is no second copy to drift — when run outside this repo it starts by
cloning it at the ref the skill release pins.

## Staying in sync

Conformance is continuous, not one-off. When a contract change merges to this
repo's `main`, `dispatch-contract-change.yml` notifies the implementation
repo (`repository_dispatch`, payload `{contract_ref}`); the implementation's
`contract-sync` workflow — installed by the skill's phase 5 from a bundled
template — then converges on the new ref:

- A `CONTRACT_REF` file in the implementation pins the contract sha it
  currently implements; a dispatch for that same sha is a no-op.
- For a new sha, an agent diffs the two contract refs to scope the change,
  updates the existing implementation minimally (never regenerates), bumps
  `CONTRACT_REF`, and pushes the deterministic branch
  `contract-sync/<sha>` — repeat runs update the same branch and PR.
- The PR merges only when the implementation's own CI passes the definition
  of done above. The agent is instructed to open a draft and report failures
  honestly rather than weaken anything to force green.
