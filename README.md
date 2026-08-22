# pizza-pattern

Design-and-mock-first demonstrator for a command-driven, event-emitting service. A `MakePizza` command is posted over HTTP, fulfilment is an internal concern, lifecycle events are emitted as CloudEvents, and consumers can poll pizza status. No internals are implemented — the contracts ([`specs/`](specs/)) and running Microcks mocks are the deliverable, so consumers can build against the service today.

## Getting started

```sh
task setup        # one-shot: installs the mise-pinned toolchain + git hooks
task docs:serve   # browse the full docs at http://localhost:8000
task ci           # full verification — the same command CI runs
```

Docker is the one prerequisite mise doesn't manage.

## Documentation

All docs live in [`docs/`](docs/) and render as the MkDocs site:

- [Overview & design](docs/index.md) — what this is, diagrams, the event model
- [Consumer quickstart](docs/quickstart.md) — run the mocks and integrate now
- [Behaviour](docs/behaviour.md) — the Gherkin rules the contracts can't express ([`specs/features/`](specs/features/))
- [Implementing the contract](docs/implementing.md) — what "done" means for an implementation (agents get it as a [skill](.claude/skills/implement-pizza-service/SKILL.md))
- [Design decisions](docs/decisions.md) — every choice, challenged and justified

## Licence

[MIT](LICENSE).
