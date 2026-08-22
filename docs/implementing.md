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
