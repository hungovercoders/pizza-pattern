# House rules: see make-pizza-idempotency.feature. Scenarios span state or
# several interactions; names are verbatim from the specs; no bindings yet.

@lifecycle
Feature: Pizza lifecycle
  A pizza only ever moves along the transitions in the state diagram
  (rendered in the docs overview). These scenarios are the normative rules
  the diagram illustrates.

  Scenario: States advance only along legal transitions
    Given a pizza whose "history" ends in state "topped"
    When the pizza next changes state
    Then its new "state" is one of "cooked", "failed" or "cancelled"

  Scenario Outline: Terminal states are final
    Given a pizza in state "<state>"
    When any further fulfilment or command processing occurs
    Then the pizza remains in state "<state>"
    And its "history" gains no further entries

    Examples:
      | state     |
      | ready     |
      | failed    |
      | cancelled |

  Scenario: History is append-only and time-ordered
    Given a pizza that has changed state at least twice
    When its status is fetched twice in succession
    Then the earlier "history" is a prefix of the later "history"
    And the "at" timestamps are non-decreasing, oldest first

  Scenario: Status is a projection of the event stream
    Given the lifecycle events published for a pizza, in order
    When its status is fetched
    Then "state" equals the state entered by the last event
    And "history" lists exactly the states those events entered, in the same order

  Scenario: Read-your-writes after acceptance
    Given a MakePizza command was just accepted with a 202
    When the returned "statusUrl" is fetched immediately
    Then the response status is 200
    And "state" is "accepted"
