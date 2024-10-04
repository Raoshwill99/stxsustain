;; STX for Sustainability: Real-World Environmental Impact Solutions
;; Fifth iteration: Complete Governance Implementation

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-verified (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-listing-not-found (err u105))
(define-constant err-price-mismatch (err u106))
(define-constant err-invalid-data-source (err u107))
(define-constant err-project-mismatch (err u108))
(define-constant err-proposal-not-found (err u109))
(define-constant err-voting-period-ended (err u110))
(define-constant err-already-voted (err u111))
(define-constant min-proposal-duration u144) ;; Minimum 1 day (in blocks, assuming 10-minute block time)

;; Define data variables
(define-data-var total-carbon-credits uint u0)
(define-data-var listing-nonce uint u0)
(define-data-var project-nonce uint u0)
(define-data-var proposal-nonce uint u0)

;; Define data maps
(define-map carbon-credits principal 
  { balance: uint, pending: uint, verified: uint })
(define-map verifiers principal bool)
(define-map listings uint 
  { seller: principal, amount: uint, price: uint })
(define-map data-sources principal bool)
(define-map project-data uint 
  { project-id: uint, carbon-reduction: uint, timestamp: uint, remaining-credits: uint })
(define-map credit-to-project principal (list 200 { credit-amount: uint, project-id: uint }))
(define-map proposals uint 
  { proposer: principal, 
    title: (string-ascii 50), 
    description: (string-ascii 500),
    link: (optional (string-utf8 256)),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 20) })
(define-map votes { proposal-id: uint, voter: principal } bool)

;; Verifier management functions
(define-public (set-verifier (new-verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set verifiers new-verifier true)
    (ok true)))

(define-public (remove-verifier (verifier-to-remove principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete verifiers verifier-to-remove)
    (ok true)))

;; Data source management functions
(define-public (set-data-source (new-source principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set data-sources new-source true)
    (ok true)))

(define-public (remove-data-source (source-to-remove principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete data-sources source-to-remove)
    (ok true)))

;; Project data input function
(define-public (input-project-data (project-id uint) (carbon-reduction uint))
  (begin
    (asserts! (default-to false (map-get? data-sources tx-sender)) err-unauthorized)
    (let ((nonce (var-get project-nonce)))
      (map-set project-data nonce 
        { project-id: project-id, 
          carbon-reduction: carbon-reduction, 
          timestamp: block-height,
          remaining-credits: carbon-reduction })
      (var-set project-nonce (+ nonce u1))
      (ok nonce))))

;; Carbon credit management functions
(define-public (register-carbon-credits (amount uint) (project-data-id uint))
  (let ((current-data (default-to { balance: u0, pending: u0, verified: u0 } 
                        (map-get? carbon-credits tx-sender)))
        (project-info (unwrap! (map-get? project-data project-data-id) err-not-found)))
    (asserts! (<= amount (get remaining-credits project-info)) err-insufficient-balance)
    (map-set carbon-credits tx-sender 
      (merge current-data { pending: (+ (get pending current-data) amount) }))
    (map-set project-data project-data-id
      (merge project-info { remaining-credits: (- (get remaining-credits project-info) amount) }))
    (map-set credit-to-project tx-sender
      (unwrap-panic (as-max-len? 
        (append (default-to (list) (map-get? credit-to-project tx-sender))
                { credit-amount: amount, project-id: project-data-id })
        u200)))
    (ok true)))

(define-public (verify-carbon-credits (account principal) (amount uint) (project-data-id uint))
  (let ((current-data (default-to { balance: u0, pending: u0, verified: u0 } 
                        (map-get? carbon-credits account)))
        (project-info (unwrap! (map-get? project-data project-data-id) err-not-found))
        (credit-projects (default-to (list) (map-get? credit-to-project account))))
    (asserts! (is-some (map-get? verifiers tx-sender)) err-unauthorized)
    (asserts! (<= amount (get pending current-data)) err-insufficient-balance)
    (asserts! (is-some (find (lambda (credit) (and (is-eq (get project-id credit) project-data-id)
                                                   (>= (get credit-amount credit) amount)))
                             credit-projects))
              err-project-mismatch)
    (map-set carbon-credits account 
      (merge current-data 
        { pending: (- (get pending current-data) amount),
          verified: (+ (get verified current-data) amount) }))
    (var-set total-carbon-credits (+ (var-get total-carbon-credits) amount))
    (ok true)))

;; Marketplace functions
(define-public (create-listing (amount uint) (price uint))
  (let ((seller-data (default-to { balance: u0, pending: u0, verified: u0 } 
                       (map-get? carbon-credits tx-sender))))
    (asserts! (<= amount (get verified seller-data)) err-insufficient-balance)
    (let ((listing-id (var-get listing-nonce)))
      (map-set listings listing-id
        { seller: tx-sender, amount: amount, price: price })
      (var-set listing-nonce (+ listing-id u1))
      (ok listing-id))))

(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found)))
    (asserts! (is-eq (get seller listing) tx-sender) err-unauthorized)
    (map-delete listings listing-id)
    (ok true)))

(define-public (buy-credits (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
        (buyer tx-sender))
    (match (stx-transfer? (get price listing) buyer (get seller listing))
      success
        (begin
          (try! (transfer-credits (get seller listing) buyer (get amount listing)))
          (map-delete listings listing-id)
          (ok true))
      error (err error))))

(define-private (transfer-credits (sender principal) (recipient principal) (amount uint))
  (let ((sender-data (default-to { balance: u0, pending: u0, verified: u0 } 
                       (map-get? carbon-credits sender)))
        (recipient-data (default-to { balance: u0, pending: u0, verified: u0 } 
                          (map-get? carbon-credits recipient))))
    (asserts! (<= amount (get verified sender-data)) err-insufficient-balance)
    (map-set carbon-credits sender 
      (merge sender-data { verified: (- (get verified sender-data) amount) }))
    (map-set carbon-credits recipient 
      (merge recipient-data { verified: (+ (get verified recipient-data) amount) }))
    (ok true)))

;; Governance functions
(define-public (create-proposal (title (string-ascii 50)) (description (string-ascii 500)) (link (optional (string-utf8 256))) (duration uint))
  (let ((proposal-id (var-get proposal-nonce))
        (start-block block-height)
        (end-block (+ block-height (max duration min-proposal-duration))))
    (map-set proposals proposal-id
      { proposer: tx-sender,
        title: title,
        description: description,
        link: link,
        start-block: start-block,
        end-block: end-block,
        yes-votes: u0,
        no-votes: u0,
        status: "active" })
    (var-set proposal-nonce (+ proposal-id u1))
    (ok proposal-id)))

(define-public (vote (proposal-id uint) (vote-bool bool))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
        (voter tx-sender))
    (asserts! (<= block-height (get end-block proposal)) err-voting-period-ended)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: voter })) err-already-voted)
    (map-set votes { proposal-id: proposal-id, voter: voter } vote-bool)
    (if vote-bool
      (map-set proposals proposal-id (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) }))
      (map-set proposals proposal-id (merge proposal { no-votes: (+ (get no-votes proposal) u1) })))
    (ok true)))

(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found)))
    (asserts! (> block-height (get end-block proposal)) err-voting-period-ended)
    (if (> (get yes-votes proposal) (get no-votes proposal))
      (map-set proposals proposal-id (merge proposal { status: "passed" }))
      (map-set proposals proposal-id (merge proposal { status: "rejected" })))
    (ok true)))

;; Read-only functions
(define-read-only (get-carbon-credits (account principal))
  (map-get? carbon-credits account))

(define-read-only (get-total-carbon-credits)
  (ok (var-get total-carbon-credits)))

(define-read-only (is-verifier (account principal))
  (default-to false (map-get? verifiers account)))

(define-read-only (is-data-source (account principal))
  (default-to false (map-get? data-sources account)))

(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id))

(define-read-only (get-all-listings)
  (let ((listings-count (var-get listing-nonce)))
    (filter is-some
      (map get-listing (unwrap-panic (slice-range-to-max u0 listings-count)))
    )
  ))

(define-read-only (get-project-data (project-data-id uint))
  (map-get? project-data project-data-id))

(define-read-only (get-credit-projects (account principal))
  (map-get? credit-to-project account))

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter }))