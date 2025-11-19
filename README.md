⚖️ PredictiveArbitration
========================

A decentralized system for managing disputes on the Stacks blockchain with **AI-powered predictive outcomes**, **multi-stage arbitration workflows**, and **reputation-based arbitrator selection**.

This contract, written in **Clarity**, implements a comprehensive dispute resolution mechanism. It allows claimants and respondents to submit disputes, leverages historical data to predict potential outcomes, routes disputes through a structured workflow, and assigns highly-reputed arbitrators to render binding decisions. The system is designed to promote fairness, transparency, and high-quality resolution through incentivization and transparent record-keeping.

* * * * *

🏗️ Architecture and Workflow
-----------------------------

The contract implements a multi-stage dispute resolution workflow, moving from initial submission to final resolution or appeal.

### Dispute Lifecycle Stages

The system tracks disputes through the following states, represented by constants:

| Constant | Value | Description |
| --- | --- | --- |
| `status-pending` | `u0` | Dispute has been created and initial stake is locked. |
| `status-evidence-collection` | `u1` | Parties are submitting supporting evidence. |
| `status-prediction-phase` | `u2` | Predictive AI model is calculating an outcome confidence score. |
| `status-arbitration` | `u3` | Qualified arbitrator(s) have been assigned and are reviewing the case. |
| `status-resolved` | `u4` | A final, binding outcome has been reached, and stakes have been distributed. |
| `status-appealed` | `u5` | The resolution is being challenged, initiating a multi-stage appeal process. |

* * * * *

⚙️ Core Mechanics
-----------------

### 1\. Predictive Outcome Engine

The system features a **Predictive Outcome Engine** that utilizes historical data stored in the `outcome-patterns` map.

-   **Data Source:** The `outcome-patterns` map tracks aggregated data by dispute **`category`** and **`evidence-type`**.

-   **Confidence Calculation:** The private function **`calculate-prediction-confidence`** assesses the reliability of the prediction. A high `total-cases` count in the historical data increases the confidence score.

-   **Threshold:** A prediction is only generated and used to guide the arbitration if its confidence score meets the **`prediction-confidence-threshold`** (`u75`, or 75%).

-   **Function:** `(generate-prediction (dispute-id uint) (evidence-type (string-ascii 20)))` is responsible for updating the dispute with a `predicted-outcome` and `prediction-confidence`.

### 2\. Reputation-Based Arbitrator Selection

Arbitrators are a critical component of the system, and their selection is governed by reputation and qualifications.

-   **Registration:** Arbitrators register using `(register-arbitrator (specializations (list 5 (string-ascii 50))))`, which locks a minimum stake (`min-stake`) and initializes their reputation at `u50`.

-   **Qualification Check:** The private function **`is-arbitrator-qualified`** verifies that an arbitrator meets the following criteria before assignment:

    -   They are `is-active`.

    -   Their `reputation-score` is ≥ `arbitrator-min-reputation` (≥u50).

    -   They have `stake-locked` ≥ `min-stake`.

-   **Incentivization:** An arbitrator's reputation is updated in `resolve-dispute` based on whether their final vote (or the final outcome they helped determine) aligned with the initial system-generated `predicted-outcome`.

    -   **Successful Prediction/Outcome:** Reputation increases by u5.

    -   **Unsuccessful Prediction/Outcome:** Reputation decreases by u5.

### 3\. Weighted Voting

While the current implementation focuses on single-arbitrator assignment, the `arbitrator-votes` map and the **`calculate-vote-weight`** function lay the groundwork for a future **multi-arbitrator panel**.

The vote weight is calculated using a formula that prioritizes both reputation and past performance:

$$\text{Vote Weight} = \text{Reputation Score} + \left( \frac{\text{Successful Predictions} \times 100}{\text{Total Cases}} \right) $$### 4\. Advanced Multi-Stage Appeal The `initiate-appeal-with-panel` function implements a robust mechanism to challenge a **`status-resolved`** dispute. * **Escalation:** The cost and panel size requirement increase with each subsequent appeal (up to a maximum of 3 appeals, $\le u2$ `appeal-count`). * **Dynamic Stake:** The required additional stake is calculated dynamically:$$

```
$$\\text{Required Stake} = (\\text{min-stake} \\times (1 + \\text{current-appeal-count})) + (\\text{requested-panel-size} \\times \\text{min-stake})
$$
$$

```

-   **Panel Requirement:** Appeals require a panel size between u3 and u7.

-   **Deadline:** Appeals must be initiated within a block deadline (`u144` blocks, approximately 24 hours) after resolution.

* * * * *

🔒 Private Functions
--------------------

These functions encapsulate the core logic for calculations, internal state checks, and data updates. They can only be called from within the contract.

### 1\. `calculate-prediction-confidence`

This function determines the reliability of the historical data used for an outcome prediction.

-   **Purpose:** Ensures predictions are backed by a statistically significant number of cases.

-   **Logic:** It returns the confidence score from the `outcome-patterns` map **only if** the `total-cases` for the specific category/evidence type is greater than u10. Otherwise, it returns u0.

### 2\. `is-arbitrator-qualified`

A critical validation function that acts as a quality-control gate for arbitrator assignment.

-   **Purpose:** Checks if an arbitrator meets the minimum requirements (stake, reputation, and activity) to be assigned a case.

-   **Validation:** Asserts that the arbitrator is **`is-active`**, their **`reputation-score`** is ≥ `arbitrator-min-reputation`, and their **`stake-locked`** is ≥ `min-stake`.

### 3\. `calculate-vote-weight`

Computes the weighted influence of an arbitrator's vote, essential for future multi-arbitrator panels.

-   **Purpose:** Calculates a weighted score by combining the arbitrator's raw `reputation` with their historical **prediction accuracy** (successful predictions vs. total cases).

### 4\. `update-outcome-pattern`

The learning mechanism of the system, responsible for integrating resolution data back into the predictive model.

-   **Purpose:** Ensures the AI model improves over time by updating the historical dataset.

-   **Updates:** Recalculates and sets `total-cases`, `claimant-wins`, **`average-resolution-time`** (using a running average), and the resulting **`confidence-score`** for the specific category/evidence type pattern.

* * * * *

🛠️ Data Structures (Maps and Variables)
----------------------------------------

### Maps

| Map Name | Key | Value | Description |
| --- | --- | --- | --- |
| `disputes` | `{ dispute-id: uint }` | Comprehensive metadata for each dispute, including status, outcome, and prediction. |  |
| `arbitrators` | `{ arbitrator: principal }` | Tracks reputation, case history, specializations, and locked stake for all registered arbitrators. |  |
| `arbitrator-votes` | `{ dispute-id: uint, arbitrator: principal }` | Records the vote, weight, and reasoning hash for an arbitrator in a specific dispute. |  |
| `outcome-patterns` | `{ category: (string-ascii 50), evidence-type: (string-ascii 20) }` | Historical data used by the predictive model for outcome probability and confidence scoring. |  |
| `evidence-submissions` | `{ dispute-id: uint, submitter: principal, submission-index: uint }` | Detailed log of all evidence and appeal submissions related to a dispute. |  |

### Data Variables

| Variable Name | Type | Initial Value | Description |
| --- | --- | --- | --- |
| `dispute-counter` | `uint` | `u0` | Auto-incrementing counter for unique dispute IDs. |
| `evidence-counter` | `uint` | `u0` | Auto-incrementing counter for evidence submission indices. |
| `arbitration-fee-percentage` | `uint` | `u5` | The percentage fee (5%) taken from the total staked amount upon resolution. |
| `prediction-enabled` | `bool` | `true` | System flag to enable/disable the predictive outcome engine. |

* * * * *

📜 Public Functions (API)
-------------------------

### `(register-arbitrator (specializations (list 5 (string-ascii 50))))`

Registers the transaction sender as an arbitrator, locking the `min-stake` and setting initial reputation.

### `(create-dispute (respondent principal) (category (string-ascii 50)) (evidence-hash (string-ascii 64)) (stake-amount uint))`

Initiates a new dispute. Locks the `stake-amount` from the claimant.

### `(submit-evidence (dispute-id uint) (evidence-hash (string-ascii 64)) (evidence-type (string-ascii 20)))`

Allows a claimant or respondent to submit evidence for an active dispute.

### `(generate-prediction (dispute-id uint) (evidence-type (string-ascii 20)))`

Triggers the predictive outcome engine. Moves the dispute to `status-prediction-phase`.

### `(assign-arbitrator (dispute-id uint) (arbitrator principal))`

Assigns a qualified arbitrator to a dispute, moving it to `status-arbitration`. Typically called by the `contract-owner`.

### `(submit-arbitrator-vote (dispute-id uint) (vote bool) (reasoning-hash (string-ascii 64)))`

Allows the assigned arbitrator to submit their binding vote.

### `(resolve-dispute (dispute-id uint) (final-outcome bool))`

Finalizes the dispute, distributes the staked funds, updates arbitrator reputation, and updates outcome patterns.

### `(initiate-appeal-with-panel (dispute-id uint) (appeal-reasoning-hash (string-ascii 64)) (additional-stake uint) (requested-panel-size uint))`

Allows a party to challenge a `status-resolved` outcome, escalating the case to a panel.

* * * * *

🛑 Contract Constants
---------------------

### Error Codes

| Error Code | Value | Description |
| --- | --- | --- |
| `err-owner-only` | `u100` | Only the contract owner can execute this function. |
| `err-not-found` | `u101` | The requested dispute or data entry does not exist. |
| `err-unauthorized` | `u102` | Transaction sender is not an authorized party. |
| `err-invalid-status` | `u103` | Function called when the dispute is in the wrong status. |
| `err-insufficient-stake` | `u104` | Insufficient stake amount is below the minimum required. |
| `err-already-voted` | `u105` | Arbitrator has already submitted a vote. |
| `err-dispute-closed` | `u106` | Dispute is resolved or appeal deadline has passed. |
| `err-invalid-prediction` | `u107` | Prediction fails confidence threshold or panel size is invalid. |
| `err-arbitrator-not-qualified` | `u108` | Arbitrator does not meet the minimum qualification requirements. |

### Configuration Constants

| Constant | Value | Description |
| --- | --- | --- |
| `min-stake` | `u1000000` | Minimum STX required for dispute stake and arbitrator lock (1 STX). |
| `arbitrator-min-reputation` | `u50` | Minimum reputation score required for arbitrator assignment. |
| `prediction-confidence-threshold` | `u75` | Minimum confidence (75%) required for the predictive model to output a suggested outcome. |

* * * * *

🤝 Contribution
---------------

We welcome contributions from the Stacks community to enhance the security, efficiency, and features of the `PredictiveArbitration` system.

1.  **Fork** the repository.

2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).

3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).

4.  Push to the branch (`git push origin feature/AmazingFeature`).

5.  Open a Pull Request.

Please ensure all Clarity code adheres to best practices, is thoroughly tested, and includes clear documentation for any new functions or data structures.

* * * * *

📜 License
----------

This project is licensed under the **MIT License**.

### MIT License

Copyright (c) 2025 Gemini

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
