;; Predictive Arbitration Workflow System
;; A decentralized system for managing disputes with AI-powered predictive outcomes,
;; multi-stage arbitration workflows, and reputation-based arbitrator selection.
;; This contract enables parties to submit disputes, predict outcomes using historical data,
;; assign arbitrators based on expertise and reputation, and execute binding decisions.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-stake (err u104))
(define-constant err-already-voted (err u105))
(define-constant err-dispute-closed (err u106))
(define-constant err-invalid-prediction (err u107))
(define-constant err-arbitrator-not-qualified (err u108))

(define-constant min-stake u1000000) ;; Minimum stake in microSTX
(define-constant arbitrator-min-reputation u50)
(define-constant prediction-confidence-threshold u75) ;; 75% confidence required

;; Dispute status constants
(define-constant status-pending u0)
(define-constant status-evidence-collection u1)
(define-constant status-prediction-phase u2)
(define-constant status-arbitration u3)
(define-constant status-resolved u4)
(define-constant status-appealed u5)

;; data maps and vars

;; Dispute tracking with comprehensive metadata
(define-map disputes
  { dispute-id: uint }
  {
    claimant: principal,
    respondent: principal,
    category: (string-ascii 50),
    stake-amount: uint,
    status: uint,
    created-at: uint,
    resolved-at: uint,
    outcome: (optional bool), ;; true = claimant wins, false = respondent wins
    predicted-outcome: (optional bool),
    prediction-confidence: uint,
    assigned-arbitrator: (optional principal),
    evidence-hash: (string-ascii 64),
    appeal-count: uint
  }
)

;; Arbitrator registry with reputation and expertise tracking
(define-map arbitrators
  { arbitrator: principal }
  {
    reputation-score: uint,
    total-cases: uint,
    successful-predictions: uint,
    specializations: (list 5 (string-ascii 50)),
    is-active: bool,
    stake-locked: uint
  }
)

;; Voting records for multi-arbitrator panels
(define-map arbitrator-votes
  { dispute-id: uint, arbitrator: principal }
  {
    vote: bool,
    reasoning-hash: (string-ascii 64),
    voted-at: uint,
    weight: uint
  }
)

;; Historical outcome data for predictive modeling
(define-map outcome-patterns
  { category: (string-ascii 50), evidence-type: (string-ascii 20) }
  {
    total-cases: uint,
    claimant-wins: uint,
    average-resolution-time: uint,
    confidence-score: uint
  }
)

;; Evidence submissions tracking
(define-map evidence-submissions
  { dispute-id: uint, submitter: principal, submission-index: uint }
  {
    evidence-hash: (string-ascii 64),
    submission-type: (string-ascii 20),
    timestamp: uint,
    verified: bool
  }
)

;; Counter for dispute IDs
(define-data-var dispute-counter uint u0)

;; Counter for evidence submissions per dispute
(define-data-var evidence-counter uint u0)

;; System configuration
(define-data-var arbitration-fee-percentage uint u5) ;; 5% fee
(define-data-var prediction-enabled bool true)

;; private functions

;; Calculate prediction confidence based on historical data
(define-private (calculate-prediction-confidence (category (string-ascii 50)) (evidence-type (string-ascii 20)))
  (let
    (
      (pattern (default-to 
        { total-cases: u0, claimant-wins: u0, average-resolution-time: u0, confidence-score: u0 }
        (map-get? outcome-patterns { category: category, evidence-type: evidence-type })
      ))
    )
    (if (> (get total-cases pattern) u10)
      (get confidence-score pattern)
      u0
    )
  )
)

;; Validate arbitrator qualifications for a specific dispute
(define-private (is-arbitrator-qualified (arbitrator principal) (category (string-ascii 50)))
  (let
    (
      (arbitrator-data (map-get? arbitrators { arbitrator: arbitrator }))
    )
    (match arbitrator-data
      arb-info
        (and
          (get is-active arb-info)
          (>= (get reputation-score arb-info) arbitrator-min-reputation)
          (>= (get stake-locked arb-info) min-stake)
        )
      false
    )
  )
)

;; Calculate weighted vote outcome
(define-private (calculate-vote-weight (reputation uint) (successful-predictions uint) (total-cases uint))
  (if (> total-cases u0)
    (+ reputation (/ (* successful-predictions u100) total-cases))
    reputation
  )
)

;; Update outcome patterns for predictive modeling
(define-private (update-outcome-pattern 
  (category (string-ascii 50)) 
  (evidence-type (string-ascii 20)) 
  (claimant-won bool)
  (resolution-time uint))
  (let
    (
      (current-pattern (default-to 
        { total-cases: u0, claimant-wins: u0, average-resolution-time: u0, confidence-score: u0 }
        (map-get? outcome-patterns { category: category, evidence-type: evidence-type })
      ))
      (new-total (+ (get total-cases current-pattern) u1))
      (new-wins (if claimant-won (+ (get claimant-wins current-pattern) u1) (get claimant-wins current-pattern)))
      (new-avg-time (/ (+ (* (get average-resolution-time current-pattern) (get total-cases current-pattern)) resolution-time) new-total))
      (new-confidence (/ (* new-wins u100) new-total))
    )
    (map-set outcome-patterns
      { category: category, evidence-type: evidence-type }
      {
        total-cases: new-total,
        claimant-wins: new-wins,
        average-resolution-time: new-avg-time,
        confidence-score: new-confidence
      }
    )
  )
)

;; public functions

;; Register as an arbitrator with specializations
(define-public (register-arbitrator (specializations (list 5 (string-ascii 50))))
  (let
    (
      (caller tx-sender)
    )
    (asserts! (>= (stx-get-balance caller) min-stake) err-insufficient-stake)
    (try! (stx-transfer? min-stake caller (as-contract tx-sender)))
    (ok (map-set arbitrators
      { arbitrator: caller }
      {
        reputation-score: u50,
        total-cases: u0,
        successful-predictions: u0,
        specializations: specializations,
        is-active: true,
        stake-locked: min-stake
      }
    ))
  )
)

;; Create a new dispute with initial stake
(define-public (create-dispute 
  (respondent principal) 
  (category (string-ascii 50))
  (evidence-hash (string-ascii 64))
  (stake-amount uint))
  (let
    (
      (dispute-id (+ (var-get dispute-counter) u1))
      (caller tx-sender)
    )
    (asserts! (>= stake-amount min-stake) err-insufficient-stake)
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
    (map-set disputes
      { dispute-id: dispute-id }
      {
        claimant: caller,
        respondent: respondent,
        category: category,
        stake-amount: stake-amount,
        status: status-pending,
        created-at: block-height,
        resolved-at: u0,
        outcome: none,
        predicted-outcome: none,
        prediction-confidence: u0,
        assigned-arbitrator: none,
        evidence-hash: evidence-hash,
        appeal-count: u0
      }
    )
    (var-set dispute-counter dispute-id)
    (ok dispute-id)
  )
)

;; Submit evidence for a dispute
(define-public (submit-evidence 
  (dispute-id uint) 
  (evidence-hash (string-ascii 64))
  (evidence-type (string-ascii 20)))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
      (caller tx-sender)
      (submission-index (+ (var-get evidence-counter) u1))
    )
    (asserts! (or (is-eq caller (get claimant dispute)) (is-eq caller (get respondent dispute))) err-unauthorized)
    (asserts! (is-eq (get status dispute) status-evidence-collection) err-invalid-status)
    (map-set evidence-submissions
      { dispute-id: dispute-id, submitter: caller, submission-index: submission-index }
      {
        evidence-hash: evidence-hash,
        submission-type: evidence-type,
        timestamp: block-height,
        verified: false
      }
    )
    (var-set evidence-counter submission-index)
    (ok submission-index)
  )
)

;; Generate predictive outcome using historical patterns
(define-public (generate-prediction (dispute-id uint) (evidence-type (string-ascii 20)))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
      (category (get category dispute))
      (confidence (calculate-prediction-confidence category evidence-type))
      (pattern (default-to 
        { total-cases: u0, claimant-wins: u0, average-resolution-time: u0, confidence-score: u0 }
        (map-get? outcome-patterns { category: category, evidence-type: evidence-type })
      ))
      (predicted-outcome (> (get claimant-wins pattern) (/ (get total-cases pattern) u2)))
    )
    (asserts! (var-get prediction-enabled) err-invalid-prediction)
    (asserts! (is-eq (get status dispute) status-evidence-collection) err-invalid-status)
    (asserts! (>= confidence prediction-confidence-threshold) err-invalid-prediction)
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute {
        predicted-outcome: (some predicted-outcome),
        prediction-confidence: confidence,
        status: status-prediction-phase
      })
    )
    (ok { predicted-outcome: predicted-outcome, confidence: confidence })
  )
)

;; Assign qualified arbitrator to dispute
(define-public (assign-arbitrator (dispute-id uint) (arbitrator principal))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
      (category (get category dispute))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-arbitrator-qualified arbitrator category) err-arbitrator-not-qualified)
    (asserts! (is-eq (get status dispute) status-prediction-phase) err-invalid-status)
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute {
        assigned-arbitrator: (some arbitrator),
        status: status-arbitration
      })
    )
    (ok true)
  )
)

;; Arbitrator submits vote with reasoning
(define-public (submit-arbitrator-vote 
  (dispute-id uint) 
  (vote bool) 
  (reasoning-hash (string-ascii 64)))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
      (caller tx-sender)
      (arbitrator-data (unwrap! (map-get? arbitrators { arbitrator: caller }) err-unauthorized))
      (vote-weight (calculate-vote-weight 
        (get reputation-score arbitrator-data)
        (get successful-predictions arbitrator-data)
        (get total-cases arbitrator-data)
      ))
    )
    (asserts! (is-eq (get status dispute) status-arbitration) err-invalid-status)
    (asserts! (is-eq (some caller) (get assigned-arbitrator dispute)) err-unauthorized)
    (asserts! (is-none (map-get? arbitrator-votes { dispute-id: dispute-id, arbitrator: caller })) err-already-voted)
    (map-set arbitrator-votes
      { dispute-id: dispute-id, arbitrator: caller }
      {
        vote: vote,
        reasoning-hash: reasoning-hash,
        voted-at: block-height,
        weight: vote-weight
      }
    )
    (ok vote-weight)
  )
)

;; Resolve dispute and distribute stakes
(define-public (resolve-dispute (dispute-id uint) (final-outcome bool))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
      (caller tx-sender)
      (stake (get stake-amount dispute))
      (fee (/ (* stake (var-get arbitration-fee-percentage)) u100))
      (payout (- stake fee))
      (winner (if final-outcome (get claimant dispute) (get respondent dispute)))
      (arbitrator (unwrap! (get assigned-arbitrator dispute) err-not-found))
      (resolution-time (- block-height (get created-at dispute)))
    )
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (is-eq (get status dispute) status-arbitration) err-invalid-status)
    
    ;; Transfer payout to winner
    (try! (as-contract (stx-transfer? payout tx-sender winner)))
    
    ;; Update dispute status
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute {
        outcome: (some final-outcome),
        status: status-resolved,
        resolved-at: block-height
      })
    )
    
    ;; Update arbitrator reputation
    (let
      (
        (arb-data (unwrap! (map-get? arbitrators { arbitrator: arbitrator }) err-not-found))
        (prediction-correct (is-eq (get predicted-outcome dispute) (some final-outcome)))
        (new-reputation (if prediction-correct 
          (+ (get reputation-score arb-data) u5)
          (if (> (get reputation-score arb-data) u5) (- (get reputation-score arb-data) u5) u0)
        ))
      )
      (map-set arbitrators
        { arbitrator: arbitrator }
        (merge arb-data {
          reputation-score: new-reputation,
          total-cases: (+ (get total-cases arb-data) u1),
          successful-predictions: (if prediction-correct 
            (+ (get successful-predictions arb-data) u1)
            (get successful-predictions arb-data)
          )
        })
      )
    )
    
    ;; Update outcome patterns for future predictions
    (update-outcome-pattern (get category dispute) "general" final-outcome resolution-time)
    
    (ok { winner: winner, payout: payout, resolution-time: resolution-time })
  )
)


