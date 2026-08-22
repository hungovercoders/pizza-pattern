# Behaviour

The contracts state every request/response and event **shape**, and the mocks
replay them — but a stateless mock cannot express rules that span state or
several interactions. Those rules live here, as Gherkin in
`specs/features/`, and are as normative as the contracts.

What qualifies for a feature file:

- **In scope**: rules the contracts cannot say — idempotent replay, legal
  lifecycle transitions, cancellation semantics, event/status consistency.
- **Out of scope**: anything a single exampled exchange already states. The
  Microcks contract tests replay those; restating them here would rot.

Who owns what: **features** state *what* must hold, the **spec examples** state
single-interaction shapes, [design decisions](decisions.md) record *why*, and
the state diagram in the [overview](index.md) illustrates what the lifecycle
feature specifies.

There are deliberately no step bindings yet — nothing exists to run them
against, and the stateless mocks cannot satisfy them. They are written to be
bound (concrete steps over the real endpoints and channel) and become the
acceptance suite for any implementation — see
[implementing the contract](implementing.md). Until then, `task lint` parses
them and checks every state they name against the `PizzaState` enum, so they
cannot silently drift from the specs.

## MakePizza idempotency

```gherkin
--8<-- "specs/features/make-pizza-idempotency.feature"
```

## Pizza lifecycle

```gherkin
--8<-- "specs/features/pizza-lifecycle.feature"
```

## CancelPizza semantics

```gherkin
--8<-- "specs/features/cancel-pizza.feature"
```

## Lifecycle event consistency

```gherkin
--8<-- "specs/features/lifecycle-events.feature"
```
