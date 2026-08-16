# Design decisions & challenges

The ticket asked for the approach to be challenged. These are the decisions taken, each with the challenge it answers.

## Command endpoint, not resource creation

`POST /commands/make-pizza` rather than `POST /pizzas`. The pizza does not exist when the request is made — the consumer is issuing a command, not creating a resource. The path makes that unmissable and extends naturally to further commands without inventing verbs on resources — `/commands/cancel-pizza` demonstrates the pattern extending.

**Challenge accepted:** command endpoints are unfamiliar to CRUD-first consumers. Mitigation: the 202 response carries a `statusUrl` and `Location` header, so the follow-your-nose experience is identical to resource creation.

## 202, not 201

Nothing the consumer owns exists at accept time. `201 Created` would promise a resource; `202 Accepted` promises only that the command was validated and fulfilment is now the service's problem. This is the contract-level expression of "the queue is an implementation detail".

## The queue stays out of the contract

The ticket mentions an internal queue. It is deliberately absent from both specs. The contract promises acceptance plus eventual events — nothing about how fulfilment happens. Naming the queue would let consumers couple to fulfilment mechanics and freeze internal refactoring.

## Polling and events — why both

`GET /pizzas/{pizzaId}` is the cheap, no-infrastructure status check; the `pizza/lifecycle` channel serves reactive consumers. Is the GET redundant? No — forcing every consumer onto a broker/WebSocket just to check status is over-engineering. The GET is documented as a projection of the same event stream (its `history` field makes that visible).

## Read-your-writes

After a 202, `GET /pizzas/{pizzaId}` must immediately return the pizza in state `accepted` — there is no 404 window. This is a real constraint on the future implementation, stated now so consumers can rely on it.

## Idempotency

`MakePizza` has no natural key, so a client retry after a network timeout would make two pizzas. The required `Idempotency-Key` header closes that: replaying a key returns the original 202 body (same `commandId`/`pizzaId`). The mock cannot enforce this (Microcks is stateless) — it is a contract promise for the implementation.

On the event side, delivery is at-least-once: consumers dedupe on `eventId`.

## Event versioning

`eventType` carries the version: `pizza.<fact>.v1`. Additive payload changes do not bump the version; breaking changes mint `pizza.<fact>.v2` published alongside `.v1` until consumers migrate.

## One channel, not channel-per-event

A single `pizza/lifecycle` channel gives per-pizza ordering with one subscription. Channel-per-event offers finer-grained subscription but loses ordering across event types — the wrong trade for a lifecycle.

## Envelope: plain JSON, CloudEvents-shaped

The envelope (`eventId`, `eventType`, `occurredAt`, plus `pizzaId`/`commandId` correlation) uses CloudEvents vocabulary without adopting CloudEvents proper, which adds `specversion` ceremony that obscures the demonstration. Upgrading later is a field-rename away.

## AsyncAPI 2.6, not 3.0

Microcks supports both, but 2.x is the well-trodden path for its example conventions (and Spectral's asyncapi ruleset). A production system starting today should evaluate 3.0. Note the 2.x trap: `subscribe` means "consumers subscribe here", i.e. events the service *publishes*.

## WebSocket is the mock transport, not a commitment

The `ws` binding in `asyncapi.yaml` exists solely so Microcks can serve the channel over WebSocket. The production transport (Kafka, webhooks, SSE, …) is deliberately undecided and not part of the contract — the same principle as keeping the queue out: consumers bind to the message shapes and channel semantics, not the transport. The channel description in the spec says so explicitly.

## Auth is deliberately deferred

The API declares no security scheme. An unenforced `bearerAuth` in the spec would teach consumers to send a token nobody validates and would codify an auth design that hasn't been done. The trade-off is explicit: adding auth later is a known breaking change for consumers, accepted in exchange for not designing auth speculatively in a spike.

## Templated mock ids: considered and rejected

Microcks could generate fresh ids per call (`{{ uuid() }}`) or echo request fields into responses. Rejected for ids on two grounds: fresh ids would break the cross-spec fixture correlation that lets consumers join the HTTP and event mocks, and — worse — a fresh `commandId` per call would mock the *opposite* of the contract's Idempotency-Key replay promise (same key → same `commandId`/`pizzaId`).

## Mock fidelity limits

Microcks is example-driven and stateless:

- The mock POST does not trigger events, and the event stream is a fixed repeating fixture — the events will not echo ids from your POST.
- Mitigation: one canonical fixture pizza (`pizzaId 11111111-…111`, `commandId 22222222-…222`) is used consistently across the OpenAPI 202 example, the GET examples, and the success-path AsyncAPI message examples, so the mocked flows correlate end-to-end.
- The GET mock serves seven fixture pizzas, one frozen per lifecycle state, under ids `…111`–`…117` (see README). Each is a distinct pizza from a distinct command (distinct `commandId`s) so the fixtures respect the one-command-one-pizza contract. The canonical `…111` returns `accepted` — exactly what the `statusUrl` should show immediately after a 202.
- The event stream tells three coherent stories: pizza `…111` succeeds (accepted → ready), pizza `…116` fails, pizza `…117` is cancelled. The `failed`/`cancelled` events appear without their precursor events on the stream — the corresponding GET fixtures' `history` carries the full story.
- The async minion replays the full example batch every tick (~3s) with no ordering guarantee within a tick, and no way to stagger examples over time (verified against Microcks source). Consumers should order by `occurredAt`/state, not arrival order.
- The `Location` header declared on the 202 is not served by the mock — Microcks does not emit response-header examples here. Use `statusUrl` from the body; the header is a contract promise for the real implementation.
- Idempotency is not enforced by the mock.
- Dispatchers make responses deterministic: any valid `size` returns the 202 example, anything else the 400 (try `"size": "banana"`); any unknown `pizzaId` returns the 404 via a FALLBACK dispatcher; `cancel-pizza` returns 202 only for `…111`, 409 otherwise.
- Responses carry simulated latency (300ms commands, 150ms status), overridable per request with `?delay=<ms>`.

Contract tests against the real implementation are future work; these specs are the source of truth they will run against.
