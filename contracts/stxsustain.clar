;; STX for Sustainability: Real-World Environmental Impact Solutions
;; Initial commit

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))

;; Define data variables
(define-data-var total-carbon-credits uint u0)

;; Define data maps
(define-map carbon-credits principal uint)

;; Define public functions
(define-public (register-carbon-credits (amount uint))
    (let ((current-balance (default-to u0 (get-carbon-credits tx-sender))))
        (begin
            (map-set carbon-credits tx-sender (+ current-balance amount))
            (var-set total-carbon-credits (+ (var-get total-carbon-credits) amount))
            (ok true))))

(define-public (transfer-carbon-credits (recipient principal) (amount uint))
    (let ((sender-balance (default-to u0 (get-carbon-credits tx-sender))))
        (if (<= amount sender-balance)
            (begin
                (map-set carbon-credits tx-sender (- sender-balance amount))
                (map-set carbon-credits recipient (+ (default-to u0 (get-carbon-credits recipient)) amount))
                (ok true))
            (err u102))))

;; Define read-only functions
(define-read-only (get-carbon-credits (account principal))
    (map-get? carbon-credits account))

(define-read-only (get-total-carbon-credits)
    (ok (var-get total-carbon-credits)))