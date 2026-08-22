# House rules for specs/features/ (the normative behaviour spec):
# - No scenario may restate a single request/response pair already exampled in
#   specs/openapi.yaml or specs/asyncapi.yaml — the Microcks contract tests
#   replay those. Every scenario here spans state or several interactions,
#   which the stateless mocks cannot verify.
# - Field, state and event names are verbatim from the specs.
# - There are deliberately no step bindings yet: these are acceptance criteria
#   for any implementation of the contracts, bindable the day one exists.

@idempotency
Feature: MakePizza idempotency
  The required Idempotency-Key header makes command submission safe to retry:
  replaying a key returns the original outcome and never makes a second pizza.

  Background:
    Given a valid MakePizza command body

  Scenario: Replaying the same Idempotency-Key returns the original result
    Given the command was accepted with Idempotency-Key "K"
    When the same command is posted again with Idempotency-Key "K"
    Then the response status is 202
    And the response carries the original "commandId" and "pizzaId"
    And no second pizza exists

  Scenario: A replay does not re-emit the accepted event
    Given the command was accepted with Idempotency-Key "K"
    And one "com.hungovercoders.pizza.accepted.v1" event was published for it
    When the same command is posted again with Idempotency-Key "K"
    Then no further "com.hungovercoders.pizza.accepted.v1" event is published for that "pizzaId"

  Scenario: Reusing an Idempotency-Key with a different body is a conflict
    Given the command was accepted with Idempotency-Key "K"
    When a different command body is posted with Idempotency-Key "K"
    Then the response status is 409
    And no second pizza exists
    And the original pizza is unchanged

  Scenario: A different Idempotency-Key makes a different pizza
    Given the command was accepted with Idempotency-Key "K"
    When the same command body is posted with a new Idempotency-Key "L"
    Then the response status is 202
    And the response carries a "pizzaId" different from the first
