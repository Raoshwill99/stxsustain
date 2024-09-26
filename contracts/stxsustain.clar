;; STX for Sustainability: Real-World Environmental Impact Solutions
;; Second iteration: Implementing verification system

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-verified (err u103))

;; Define data variables
(define-data-var total-carbon-credits uint u0)
(define-data-var verifier principal contract-owner)

;; Define data maps
(define-map carbon-credits principal 
  { balance: uint, pending: uint, verified: uint })
(define-map verifiers principal bool)

;; Define functions
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
    (asserts! (<= amount (get verified sender-data)) err-not-found)
    (map-set carbon-credits tx-sender 
      (merge sender-data { verified: (- (get verified sender-data) amount) }))
    (map-set carbon-credits recipient 
      (merge recipient-data { verified: (+ (get verified recipient-data) amount) }))
    (ok true)))

;; Define read-only functions
(define-read-only (get-carbon-credits (account principal))
  (map-get? carbon-credits account))

(define-read-only (get-total-carbon-credits)
  (ok (var-get total-carbon-credits)))

(define-read-only (is-verifier (account principal))
  (default-to false (map-get? verifiers account)))