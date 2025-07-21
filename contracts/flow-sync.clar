;; FlowSync - Next-Generation Payment Channel Protocol
;;
;; EXECUTIVE SUMMARY:
;; FlowSync revolutionizes digital payments by creating secure, instant, and
;; scalable off-chain transaction networks. Built on cutting-edge cryptographic
;; primitives, it enables millions of transactions per second while maintaining
;; absolute security through blockchain-anchored dispute resolution.

;; SYSTEM CONSTANTS & ERROR HANDLING

(define-constant CONTRACT-OWNER tx-sender)

;; Authorization & Access Control Errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CHANNEL-EXISTS (err u101))
(define-constant ERR-CHANNEL-NOT-FOUND (err u102))

;; Financial Security & Validation Errors
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-INVALID-SIGNATURE (err u104))

;; Channel State & Lifecycle Errors
(define-constant ERR-CHANNEL-CLOSED (err u105))
(define-constant ERR-DISPUTE-PERIOD (err u106))
(define-constant ERR-INVALID-INPUT (err u107))

;; Security limits
(define-constant MAX-BALANCE u1000000000000) ;; 1M STX in microSTX

;; CORE DATA STRUCTURES

(define-map payment-channels
  {
    channel-id: (buff 32),
    participant-a: principal,
    participant-b: principal,
  }
  {
    total-deposited: uint,
    balance-a: uint,
    balance-b: uint,
    is-open: bool,
    dispute-deadline: uint,
    nonce: uint,
  }
)

;; INPUT VALIDATION & SECURITY LAYER

(define-private (is-valid-channel-id (channel-id (buff 32)))
  (and
    (> (len channel-id) u0)
    (<= (len channel-id) u32)
  )
)

(define-private (is-valid-deposit (amount uint))
  (and 
    (> amount u0)
    (<= amount MAX-BALANCE)
  )
)

(define-private (is-valid-balance (balance uint))
  (and
    (>= balance u0)
    (<= balance MAX-BALANCE)
  )
)

(define-private (is-valid-signature (signature (buff 65)))
  (is-eq (len signature) u65)
)

;; Enhanced validation for balance pairs
(define-private (are-valid-balances (balance-a uint) (balance-b uint) (total uint))
  (and
    (is-valid-balance balance-a)
    (is-valid-balance balance-b)
    (is-eq total (+ balance-a balance-b))
    (<= (+ balance-a balance-b) MAX-BALANCE)
  )
)

;; CRYPTOGRAPHIC UTILITIES & PRIMITIVES

(define-private (uint-to-buff (n uint))
  ;; Convert uint to buffer by hashing the uint directly
  ;; This provides a consistent 32-byte representation for any uint
  (sha256 n)
)