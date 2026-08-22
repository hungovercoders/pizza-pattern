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

`MakePizza` has no natural key, so a client retry after a network timeout would make two pizzas. The required `Idempotency-Key` header closes that: replaying a key returns the original 202 body (same `commandId`/`pizzaId`). The mock cannot enforce this (Microcks is stateless) — it is a contract promise for the implementation, stated normatively in `specs/features/make-pizza-idempotency.feature`.

Reusing a key with a **different** body returns `409` rather than silently replaying the original result, which would hide a client bug. The 409 is declared in the spec without an example — the stateless mock cannot detect reuse, so mocking it would misrepresent the rule — and stated normatively in the same feature file.

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

All documentation lives as real pages under `docs/` (the MkDocs docs_dir): overview, quickstart, this document, and the rendered API contracts. Only `docs/specs` and `docs/examples.http` are symlinks, so Swagger UI and the raw-spec links serve the exact files Microcks mocks from — one source of truth for the contracts. The root README is a deliberately thin GitHub landing page linking into `docs/`, not a duplicate of it. Swagger UI is bundled statically and the AsyncAPI reference is generated as a self-contained HTML page, so the built site works fully offline. Publishing is deferred: the repo is now public so GitHub Pages is available — hosting the built site is a follow-up, not part of this spike.

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
- The async minion replays the full example batch every tick (~30s; one of Microcks' allowed frequencies 3/10/30) with no ordering guarantee within a tick, and no way to stagger examples over time (verified against Microcks source). Consumers should order by the CloudEvent `time`/state, not arrival order.
- The `Location` header declared on the 202 is not served by the mock — Microcks does not emit response-header examples here. Use `statusUrl` from the body; the header is a contract promise for the real implementation.
- Idempotency is not enforced by the mock.
- Dispatchers make responses deterministic: any valid `size` returns the 202 example, anything else the 400 (try `"size": "banana"`); any unknown `pizzaId` returns the 404 via a FALLBACK dispatcher; `cancel-pizza` returns 202 only for `…111`, 409 otherwise.
- Responses carry simulated latency (300ms commands, 150ms status), overridable per request with `?delay=<ms>`.

`task mocks:contract` tests the mock itself against these specs (below); the same runner is what will be pointed at the real implementation.

## Contract tests: the mock is the first implementation under test

`task mocks:contract` asks Microcks to run its own test runners back against the running mocks: the OpenAPI runner replays every request example against the HTTP mock and validates each response against the schema for the status code it returned; the AsyncAPI runner subscribes to the WebSocket channel for a full publication cycle and validates every CloudEvent against its message schema. Both run in `task ci`, so a mock that stops matching its contract fails the build.

**Challenge accepted:** testing a mock against the contract it was generated from is close to a tautology — it cannot fail the way a real implementation can, and it must not be mistaken for evidence that anything is implemented. It earns its place on two other grounds.

It is a regression test on the *mock chain*, which is this repo's actual deliverable and has already proven fragile: an examples artifact uploaded as a main artifact silently replaces the whole event service, a `ws` binding in the wrong place downgrades the channel to Kafka, an unnamed message example is dropped on import (all documented above, all found the hard way). Each of those leaves a mock that still answers but no longer matches the spec. `task mocks:test` would not catch them — it asserts on a handful of hand-picked fields — whereas the runner validates every example-driven exchange against the schema. The runner is therefore made to fail when it validated *zero* exchanges: against a mock generated from the spec, a green result over an empty exchange list is the likeliest real failure, not a pass.

The tautology objection also underestimated it in practice: on its very first run it caught two real contract defects. The POST request examples carried no `Idempotency-Key`, so replaying them tripped the mock's own required-header constraint (fixed with named header examples paired to each request — the spec's examples are now complete requests). And the event channel's `oneOf` could not discriminate: `PizzaBoxed`'s open `data` schema accepted *every* event's payload, so nothing validated against exactly one message (fixed with a `const` on each message's CloudEvent `type` and `additionalProperties: false` on each `data` — a strictly better contract for consumers too).

And it is the same command the real service will be tested with. Contract testing means the consumer-facing contract is verified against whatever is serving it; today that is the mock, and swapping `testEndpoint` for a deployed URL turns these into acceptance tests with no new tooling and no second definition of "correct".

The endpoints under test are the in-network ones (`microcks:8080`, `async-minion:8081`) because Microcks executes the tests itself — the published `localhost` ports are for the developer, not the runner. Async tests are dispatched to the minion, so the app needs `ASYNC_MINION_URL` pointing at this compose stack's service name.

## Behaviour lives in Gherkin, scoped to what the contracts can't say

The contracts and their examples state every single request/response and event shape, and the Microcks runners already replay and validate all of them. But rules that span state or several interactions — Idempotency-Key replay, legal lifecycle transitions, cancellation semantics, event/status consistency — cannot be expressed in OpenAPI or AsyncAPI and cannot be verified by a stateless mock. Until now they existed only as prose scattered through this file and an illustrative state diagram. They now live as Gherkin in `specs/features/`, which is as normative as the contracts.

The scoping rule is strict, because unscoped BDD is a rot machine: no scenario may restate a single exampled exchange. Everything considered and rejected for the same duplication reason: request/response Gherkin (the spec examples plus contract tests already cover it), architecture or C4 docs (they would describe the internals this design deliberately keeps out of the contract), a domain glossary (the domain is seven states and two commands, all enumerated in the specs), an error catalog (in the OpenAPI responses), and a test-plan document (the executable definition of done on the implementing page is strictly better).

The features carry no step bindings — nothing exists to run them against, and bindings without an implementation are placeholder code. To keep unexecuted Gherkin from drifting, `task lint` parses the files on every commit and CI run and checks every state named in an Examples table against the `PizzaState` enum. When an implementation exists, the features are its acceptance suite, alongside the contract-test runners pointed at its endpoints.

## Breaking-change gate on the specs

The contract tests are self-referential — the mock is generated from the spec it is tested against — so a breaking spec change sails through them as long as it is internally consistent, while breaking every consumer already integrated against the published version. `task check:compat` (in `task ci`) closes that: it diffs both specs against `origin/main` and fails on breaking changes unless the spec's `info.version` was bumped, which is the deliberate opt-out for intentional breaks.

OpenAPI uses `oasdiff breaking`, which understands request/response direction (narrowing a request enum is breaking; narrowing a response enum is not). AsyncAPI is harder: `asyncapi diff`'s breaking classifier does not reach into payload schemas — removing a whole message from the channel `oneOf` classifies as nothing at all. Rather than ship a gate that silently checks nothing, the AsyncAPI side is structural: any removal or edit (ignoring parser noise and prose fields) fails, additions pass. That is deliberately conservative for this repo, where even example edits are consumer-visible — the examples *are* the mock.

## The definition of done ships as a skill

An agent implementing these contracts needs the same two things a human implementer does: the genuinely free choices surfaced up front, and the verification loop enforced at the end. `skills/implement-pizza-service/SKILL.md` encodes that process for Claude Code — interview (language, hosting, event transport, storage: the choices the contract deliberately leaves open), build from the contract files, then loop the three definition-of-done checks until green.

The skill deliberately contains no contract content: it points at the specs, features and docs and forbids paraphrasing them, because a skill that restated the rules would be a second copy that drifts — the same scoping principle as the Gherkin decision above. It also refuses to interview about anything the contract already decides (endpoints, states, envelope, idempotency semantics), routing those to the contract-change path (`task check:compat`, version bump) instead of letting an implementation quietly renegotiate the contract.

## The skill ships via a marketplace — the contracts stay home

The repo doubles as a Claude Code plugin marketplace (`.claude-plugin/marketplace.json` + plugin manifest), so `implement-pizza-service` is installable into any project with `/plugin marketplace add hungovercoders/pizza-pattern`. The skill lives at the plugin-conventional `skills/` root; a symlink from `.claude/skills/` keeps the open-this-repo auto-discovery working — the same symlink trick the docs tree uses.

The alternative — embedding the specs in the plugin artifact so it is self-contained — was rejected: a frozen copy forks the single source of truth, drifts the moment the contract evolves, and bypasses `task check:compat` entirely. Instead the skill bootstraps by pinned clone when run outside the repo, so the contracts and the whole verification harness arrive together. Versioning falls out naturally: each plugin release pins the contract ref it implements (currently `main`; a tag once the contracts are tagged). If more skills accumulate across hungovercoders repos, this marketplace can migrate to an org-wide one without moving the plugin.
