# House rules: see make-pizza-idempotency.feature. Scenarios span state or
# several interactions; names are verbatim from the specs; no bindings yet.

@events
Feature: Lifecycle event consistency
  The HTTP status projection and the pizza/lifecycle channel describe the same
  facts — the rules tying them together live here.

  Scenario: Every state change publishes exactly one event
    Given a pizza and the "history" its status reports
    Then exactly one lifecycle event was published per "history" entry
    And each event's "type" is the one that enters that entry's "state"
    And each event's "time" equals that entry's "at"

  Scenario: Events carry the identities that join the two contracts
    Given the 202 response for an accepted command
    When the lifecycle events for that pizza are published
    Then every event's "subject" equals the response "pizzaId"
    And every event caused by that command carries its "commandId" as "commandid"
    And every event's "id" is unique

  Scenario: Redelivery must be tolerated
    Given delivery is at-least-once
    When a consumer receives two events with the same "id"
    Then processing the second must not change consumer-observable state
