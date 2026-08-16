# Design decisions & challenges

The ticket asked for the approach to be challenged. These are the decisions taken, each with the challenge it answers.

## Command endpoint, not resource creation

`POST /commands/make-pizza` rather than `POST /pizzas`. The pizza does not exist when the request is made — the consumer is issuing a command, not creating a resource. The path makes that unmissable and extends naturally to future commands (`/commands/cancel-pizza`) without inventing verbs on resources.

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

## Mock fidelity limits

Microcks is example-driven and stateless:

- The mock POST does not trigger events, and the event stream is a fixed repeating fixture — the events will not echo ids from your POST.
- Mitigation: one canonical fixture pizza (`pizzaId 11111111-…`, `commandId 22222222-…`) is used consistently across the OpenAPI 202 example, the GET example, and every AsyncAPI message example, so the mocked flows correlate end-to-end.
- Idempotency is not enforced by the mock.
- A JSON_BODY dispatcher makes HTTP responses deterministic: any valid `size` returns the 202 example; anything else returns the 400 problem example (try `"size": "banana"`).

Contract tests against the real implementation are future work; these specs are the source of truth they will run against.
