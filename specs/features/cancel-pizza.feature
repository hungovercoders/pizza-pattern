# House rules: see make-pizza-idempotency.feature. Scenarios span state or
# several interactions; names are verbatim from the specs; no bindings yet.

@cancellation
Feature: CancelPizza semantics
  Whether a cancel is accepted depends on the pizza's current state — a rule
  no single exampled exchange can express.

  Scenario Outline: Cancelling a pizza that is still in progress
    Given a pizza in non-terminal state "<state>"
    When a CancelPizza command for its "pizzaId" is accepted
    Then the cancel response status is 202
    And it carries the same "pizzaId" with a new "commandId"
    And the pizza reaches state "cancelled"
    And one "com.hungovercoders.pizza.cancelled.v1" event is published with "cancelledFrom" "<state>"

    Examples:
      | state    |
      | accepted |
      | topped   |
      | cooked   |
      | boxed    |

  Scenario Outline: Cancelling a finished pizza is rejected
    Given a pizza in terminal state "<state>"
    When a CancelPizza command for its "pizzaId" is posted
    Then the response status is 409
    And the pizza remains in state "<state>"
    And no "com.hungovercoders.pizza.cancelled.v1" event is published

    Examples:
      | state     |
      | ready     |
      | failed    |
      | cancelled |
