;; STX for Sustainability: Real-World Environmental Impact Solutions
;; Third iteration: Complete Marketplace Implementation

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-verified (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-listing-not-found (err u105))
(define-constant err-price-mismatch (err u106))

;; Define data variables
(define-data-var total-carbon-credits uint u0)
(define-data-var listing-nonce uint u0)

;; Define data maps
(define-map carbon-credits principal 
  { balance: uint, pending: uint, verified: uint })
(define-map verifiers principal bool)
(define-map listings uint 
  { seller: principal, amount: uint, price: uint })

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

;; Carbon credit management functions
(define-public (register-carbon-credits (amount uint))
  (let ((current-data (default-to { balance: u0, pending: u0, verified: u0 } 
                        (map-get? carbon-credits tx-sender))))
    (map-set carbon-credits tx-sender 
      (merge current-data { pending: (+ (get pending current-data) amount) }))
    (ok true)))

(define-public (verify-carbon-credits (account principal) (amount uint))
  (let ((current-data (default-to { balance: u0, pending: u0, verified: u0 } 
                        (map-get? carbon-credits account))))
    (asserts! (is-some (map-get? verifiers tx-sender)) err-unauthorized)
    (asserts! (<= amount (get pending current-data)) err-not-found)
    (map-set carbon-credits account 
      (merge current-data 
        { pending: (- (get pending current-data) amount),
          verified: (+ (get verified current-data) amount) }))
    (var-set total-carbon-credits (+ (var-get total-carbon-credits) amount))
    (ok true)))

(define-public (transfer-carbon-credits (recipient principal) (amount uint))
  (let ((sender-data (default-to { balance: u0, pending: u0, verified: u0 } 
                       (map-get? carbon-credits tx-sender)))
        (recipient-data (default-to { balance: u0, pending: u0, verified: u0 } 
                          (map-get? carbon-credits recipient))))
    (asserts! (<= amount (get verified sender-data)) err-insufficient-balance)
    (map-set carbon-credits tx-sender 
      (merge sender-data { verified: (- (get verified sender-data) amount) }))
    (map-set carbon-credits recipient 
      (merge recipient-data { verified: (+ (get verified recipient-data) amount) }))
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

;; Read-only functions
(define-read-only (get-carbon-credits (account principal))
  (map-get? carbon-credits account))

(define-read-only (get-total-carbon-credits)
  (ok (var-get total-carbon-credits)))

(define-read-only (is-verifier (account principal))
  (default-to false (map-get? verifiers account)))

(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id))

(define-read-only (get-all-listings)
  (let ((listings-count (var-get listing-nonce)))
    (filter is-some
      (map get-listing (unwrap-panic (slice-range-to-max u0 listings-count)))
    )
  ))