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

On the event side, delivery is at-least-once: consumers dedupe on the CloudEvent `id`.

## Event versioning

The CloudEvent `type` carries the version: `com.hungovercoders.pizza.<fact>.v1`. Additive payload changes do not bump the version; breaking changes mint `.v2` published alongside `.v1` until consumers migrate.

## One channel, not channel-per-event

A single `pizza/lifecycle` channel gives per-pizza ordering with one subscription. Channel-per-event offers finer-grained subscription but loses ordering across event types — the wrong trade for a lifecycle.

## Envelope: CloudEvents 1.0, structured mode

Originally the envelope was "CloudEvents-shaped but plain JSON" to keep the demonstration minimal; that decision explicitly reserved a field-rename upgrade path, and it has now been taken. Events are CloudEvents 1.0 in structured content mode: `id` (dedupe key), reverse-DNS `type` carrying the version (`com.hungovercoders.pizza.<fact>.v1`), `source` identifying the service, `time`, `datacontenttype: application/json`, and per-event `data` unchanged. Correlation: the pizza identity lives in the standard `subject` attribute (so generic CE tooling can filter/route on it; it matches the HTTP `pizzaId`), and the causing command in the `commandid` extension attribute (CE extension names are lowercase). The HTTP API deliberately keeps its `pizzaId`/`commandId` field names — CloudEvents is an event-envelope concern, not a REST resource shape.

Mock-chain note: messages keep `defaultContentType: application/json` rather than `application/cloudevents+json` — no functional gain in the Microcks/docs chain and a real media-type such as binary content mode is a per-transport decision for the real implementation.

## AsyncAPI 2.6, not 3.x — upgrade evaluated and blocked

Evaluated upgrading to AsyncAPI 3.1 (latest) on 2026-08-16. Everything in our chain is v3-ready — Spectral validates 3.x, `@asyncapi/html-template` renders it, Microcks imports it — **except** for a Microcks importer bug that gates the upgrade: for an operation referencing multiple messages (the v3 equivalent of our 2.6 `oneOf`), only the **last** message's examples survive import ([microcks#2273](https://github.com/microcks/microcks/issues/2273), reproduced on 1.10.1 and 1.15.0, order-dependent last-one-wins). Our single `send` operation with seven messages would mock only `PizzaCancelled`.

Workarounds considered and rejected: seven separate `send` operations (one WS endpoint each — destroys the single-subscription, per-pizza-ordering contract); a Microcks `APIExamples` secondary artifact (duplicates every example payload — breaks spec-as-single-source-of-truth).

Unblock: a Microcks release fixing #2273 — fix with regression test proposed in [microcks#2274](https://github.com/microcks/microcks/pull/2274) — then migrate. Notes for that migration: channels/operations split with `action: send` (v3 describes the *application's* behaviour — our service sends); keep the operation key literally `pizza/lifecycle` to preserve the mock WS URL (Microcks derives the WS path from the operation key for non-parametrized channels); message examples keep their `{name, payload}` shape; `x-microcks-operation` moves onto the operation; root `tags` move into `info`; server `url` becomes `host` + `protocol`.

The 2.x trap still applies meanwhile: `subscribe` means "consumers subscribe here", i.e. events the service *publishes*. Spectral's `asyncapi-latest-version` nudge is disabled in `.spectral.yaml` pointing at this decision.

## WebSocket is the mock transport, not a commitment

The `ws` binding in `asyncapi.yaml` exists solely so Microcks can serve the channel over WebSocket. The production transport (Kafka, webhooks, SSE, …) is deliberately undecided and not part of the contract — the same principle as keeping the queue out: consumers bind to the message shapes and channel semantics, not the transport. The channel description in the spec says so explicitly.

## Auth is deliberately deferred

The API declares no security scheme. An unenforced `bearerAuth` in the spec would teach consumers to send a token nobody validates and would codify an auth design that hasn't been done. The trade-off is explicit: adding auth later is a known breaking change for consumers, accepted in exchange for not designing auth speculatively in a spike.

## Templated mock ids: considered and rejected

Microcks could generate fresh ids per call (`{{ uuid() }}`) or echo request fields into responses. Rejected for ids on two grounds: fresh ids would break the cross-spec fixture correlation that lets consumers join the HTTP and event mocks, and — worse — a fresh `commandId` per call would mock the *opposite* of the contract's Idempotency-Key replay promise (same key → same `commandId`/`pizzaId`).

## Docs render from the contract files, not copies

The MkDocs site renders the README, this document, and both API contracts from the exact files Microcks mocks from — `docs-src/` is a symlink tree, so there is a single source of truth for specs and docs alike. Swagger UI is bundled statically and the AsyncAPI reference is generated as a self-contained HTML page, so the built site works fully offline. Publishing is deferred: the repo is private, which rules out free GitHub Pages; Cloudflare Pages is the likely route if/when a hosted site is wanted.

## Async triggers: POSTs publish a real contextualized event (Microcks 1.15)

A Microcks async trigger on `makePizza` publishes a contextualized `pizza.accepted.v1` over the same WebSocket channel whenever the mock is invoked, rendered from the actual exchange: `data` echoes the consumer's request (`size`/`crust`/`toppings`), `pizzaId`/`commandId` come from the mock's 202 response — i.e. the canonical fixture ids, deliberately. That *reinforces* the "Templated mock ids: considered and rejected" decision rather than contradicting it: the payload is live, the identities stay correlated with the GET fixtures and the Idempotency-Key replay promise.

Design constraints, verified in the Microcks source and empirically:

- **make-pizza only, one contextualized event.** A trigger fires *all* contextualized messages of the referenced service — the operation name in the trigger string is parsed but not used for filtering (`ProducerManager.triggerAsyncMockMessages`). A contextualized `PizzaCancelled` would therefore also fire on every make-pizza POST. Until Microcks supports trigger→message scoping (enhancement requested upstream), `cancel-pizza` stays trigger-less.
- **One event, not a staggered lifecycle.** Triggered messages fire immediately with no per-message delay or sequencing support, so mocking "accepted now, cooked in four minutes" is not possible.
- **Triggers fire on error responses too.** The trigger runs on every dispatched response, including the 400: an invalid POST emits a junk event with empty `pizzaId`/`commandId` (confirmed). Consumers should ignore events with empty `pizzaId`.
- **The template lives in a secondary `APIExamples` artifact** (`mocks/pizza-lifecycle-events.examples.yaml`), not in `specs/asyncapi.yaml`: the `{{ }}` expressions are mock plumbing, not contract — in-spec they would fail Spectral's example-vs-schema validation and leak into the rendered consumer docs. The earlier rejection of `APIExamples` was about *duplicating* the seven fixtures; this is a single additive mock-only message, so the spec remains the single source of truth for the contract. The payload is a raw-JSON block string so the `toppings` array expression renders unquoted.
- **Contextualized-vs-ambient split is automatic and content-based**: Microcks classifies any example containing `request.`/`response.` as contextualized and excludes it from the ambient 30s batch (which is why the fixture payloads must never contain those literals).
- The triggered event is dispatched before the mock's simulated latency elapses, so it can arrive *before* the 202 — subscribe first.

## Mock fidelity limits

Microcks is example-driven and stateless:

- The mock POST does not trigger events, and the event stream is a fixed repeating fixture — the events will not echo ids from your POST.
- Mitigation: one canonical fixture pizza (`pizzaId 11111111-…111`, `commandId 22222222-…222`) is used consistently across the OpenAPI 202 example, the GET examples, and the success-path AsyncAPI message examples, so the mocked flows correlate end-to-end.
- The GET mock serves seven fixture pizzas, one frozen per lifecycle state, under ids `…111`–`…117` (see README). Each is a distinct pizza from a distinct command (distinct `commandId`s) so the fixtures respect the one-command-one-pizza contract. The canonical `…111` returns `accepted` — exactly what the `statusUrl` should show immediately after a 202.
- The event stream tells three coherent stories: pizza `…111` succeeds (accepted → ready), pizza `…116` fails, pizza `…117` is cancelled. The `failed`/`cancelled` events appear without their precursor events on the stream — the corresponding GET fixtures' `history` carries the full story.
- The async minion replays the full example batch every tick (~30s; one of Microcks' allowed frequencies 3/10/30) with no ordering guarantee within a tick, and no way to stagger examples over time (verified against Microcks source). Consumers should order by `occurredAt`/state, not arrival order.
- The `Location` header declared on the 202 is not served by the mock — Microcks does not emit response-header examples here. Use `statusUrl` from the body; the header is a contract promise for the real implementation.
- Idempotency is not enforced by the mock.
- Dispatchers make responses deterministic: any valid `size` returns the 202 example, anything else the 400 (try `"size": "banana"`); any unknown `pizzaId` returns the 404 via a FALLBACK dispatcher; `cancel-pizza` returns 202 only for `…111`, 409 otherwise.
- Responses carry simulated latency (300ms commands, 150ms status), overridable per request with `?delay=<ms>`.

Contract tests against the real implementation are future work; these specs are the source of truth they will run against.
