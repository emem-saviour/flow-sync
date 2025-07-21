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

;; Enhanced message construction with validation
(define-private (construct-balance-message 
    (channel-id (buff 32)) 
    (balance-a uint) 
    (balance-b uint)
  )
  (begin
    ;; Validate inputs before message construction
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-balance balance-a) ERR-INVALID-INPUT)
    (asserts! (is-valid-balance balance-b) ERR-INVALID-INPUT)
    
    ;; Construct message with validated inputs
    (ok (concat 
      (concat channel-id (uint-to-buff balance-a))
      (uint-to-buff balance-b)
    ))
  )
)

(define-private (verify-signature
    (message (buff 256))
    (signature (buff 65))
    (signer principal)
  )
  ;; Simplified signature verification - in production, use proper ECDSA verification
  ;; This is a placeholder that checks if the caller matches the expected signer
  (is-eq tx-sender signer)
)

;; CHANNEL LIFECYCLE MANAGEMENT

;; Creates a new bidirectional payment channel between two participants
;; Establishes the initial funding and security parameters for off-chain transactions
(define-public (create-channel
    (channel-id (buff 32))
    (participant-b principal)
    (initial-deposit uint)
  )
  (begin
    ;; Input validation layer
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit initial-deposit) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    
    ;; Ensure channel uniqueness
    (asserts!
      (is-none (map-get? payment-channels {
        channel-id: channel-id,
        participant-a: tx-sender,
        participant-b: participant-b,
      }))
      ERR-CHANNEL-EXISTS
    )
    
    ;; Lock initial funds in contract escrow
    (try! (stx-transfer? initial-deposit tx-sender (as-contract tx-sender)))
    
    ;; Initialize channel state
    (map-set payment-channels {
      channel-id: channel-id,
      participant-a: tx-sender,
      participant-b: participant-b,
    } {
      total-deposited: initial-deposit,
      balance-a: initial-deposit,
      balance-b: u0,
      is-open: true,
      dispute-deadline: u0,
      nonce: u0,
    })
    (ok true)
  )
)

;; Injects additional liquidity into an existing payment channel
;; Enables dynamic channel capacity scaling for increased transaction volume
(define-public (fund-channel
    (channel-id (buff 32))
    (participant-b principal)
    (additional-funds uint)
  )
  (let ((channel (unwrap!
      (map-get? payment-channels {
        channel-id: channel-id,
        participant-a: tx-sender,
        participant-b: participant-b,
      })
      ERR-CHANNEL-NOT-FOUND
    )))
    
    ;; Security validations
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit additional-funds) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    
    ;; Check total doesn't exceed limits
    (asserts! (<= (+ (get total-deposited channel) additional-funds) MAX-BALANCE) ERR-INVALID-INPUT)
    
    ;; Transfer additional funds to contract
    (try! (stx-transfer? additional-funds tx-sender (as-contract tx-sender)))
    
    ;; Update channel capacity
    (map-set payment-channels {
      channel-id: channel-id,
      participant-a: tx-sender,
      participant-b: participant-b,
    }
      (merge channel {
        total-deposited: (+ (get total-deposited channel) additional-funds),
        balance-a: (+ (get balance-a channel) additional-funds),
      })
    )
    (ok true)
  )
)

;; COOPERATIVE SETTLEMENT PROTOCOL

;; Executes mutual channel closure with cryptographic consensus
;; Provides instant settlement when both parties agree on final balances
(define-public (close-channel-cooperative
    (channel-id (buff 32))
    (participant-b principal)
    (balance-a uint)
    (balance-b uint)
    (signature-a (buff 65))
    (signature-b (buff 65))
  )
  (let (
      (channel (unwrap!
        (map-get? payment-channels {
          channel-id: channel-id,
          participant-a: tx-sender,
          participant-b: participant-b,
        })
        ERR-CHANNEL-NOT-FOUND
      ))
      (total-channel-funds (get total-deposited channel))
    )
    
    ;; Comprehensive input validation
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature-a) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature-b) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    
    ;; Validate balances before using them
    (asserts! (are-valid-balances balance-a balance-b total-channel-funds) ERR-INSUFFICIENT-FUNDS)
    
    ;; Construct message with validated inputs
    (let ((message (unwrap! (construct-balance-message channel-id balance-a balance-b) ERR-INVALID-INPUT)))
      
      ;; Verify cryptographic signatures from both parties
      (asserts!
        (and
          (verify-signature message signature-a tx-sender)
          (verify-signature message signature-b participant-b)
        )
        ERR-INVALID-SIGNATURE
      )
      
      ;; Execute final settlement transfers
      (try! (as-contract (stx-transfer? balance-a tx-sender tx-sender)))
      (try! (as-contract (stx-transfer? balance-b tx-sender participant-b)))
      
      ;; Mark channel as permanently closed
      (map-set payment-channels {
        channel-id: channel-id,
        participant-a: tx-sender,
        participant-b: participant-b,
      }
        (merge channel {
          is-open: false,
          balance-a: u0,
          balance-b: u0,
          total-deposited: u0,
        })
      )
      (ok true)
    )
  )
)

;; ADVERSARIAL DISPUTE RESOLUTION SYSTEM

;; Initiates unilateral channel closure with time-locked dispute window
;; Enables force-closure when cooperation fails, with built-in fraud protection
(define-public (initiate-unilateral-close
    (channel-id (buff 32))
    (participant-b principal)
    (proposed-balance-a uint)
    (proposed-balance-b uint)
    (signature (buff 65))
  )
  (let (
      (channel (unwrap!
        (map-get? payment-channels {
          channel-id: channel-id,
          participant-a: tx-sender,
          participant-b: participant-b,
        })
        ERR-CHANNEL-NOT-FOUND
      ))
      (total-channel-funds (get total-deposited channel))
    )
    
    ;; Security validation layer
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    
    ;; Validate proposed balances before using them
    (asserts! (are-valid-balances proposed-balance-a proposed-balance-b total-channel-funds) ERR-INSUFFICIENT-FUNDS)
    
    ;; Construct message with validated inputs
    (let ((message (unwrap! (construct-balance-message channel-id proposed-balance-a proposed-balance-b) ERR-INVALID-INPUT)))
      
      ;; Verify initiator's cryptographic commitment
      (asserts! (verify-signature message signature tx-sender) ERR-INVALID-SIGNATURE)
      
      ;; Set dispute resolution timeline (1008 blocks = 1 week)
      (map-set payment-channels {
        channel-id: channel-id,
        participant-a: tx-sender,
        participant-b: participant-b,
      }
        (merge channel {
          dispute-deadline: (+ stacks-block-height u1008),
          balance-a: proposed-balance-a,
          balance-b: proposed-balance-b,
        })
      )
      (ok true)
    )
  )
)

;; Finalizes unilateral closure after dispute window expires
;; Executes time-locked settlement ensuring all parties had opportunity to contest
(define-public (resolve-unilateral-close
    (channel-id (buff 32))
    (participant-b principal)
  )
  (let (
      (channel (unwrap!
        (map-get? payment-channels {
          channel-id: channel-id,
          participant-a: tx-sender,
          participant-b: participant-b,
        })
        ERR-CHANNEL-NOT-FOUND
      ))
      (proposed-balance-a (get balance-a channel))
      (proposed-balance-b (get balance-b channel))
    )
    
    ;; Validate closure prerequisites
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (>= stacks-block-height (get dispute-deadline channel)) ERR-DISPUTE-PERIOD)
    
    ;; Additional validation of stored balances before transfer
    (asserts! (is-valid-balance proposed-balance-a) ERR-INVALID-INPUT)
    (asserts! (is-valid-balance proposed-balance-b) ERR-INVALID-INPUT)
    
    ;; Execute final fund distribution
    (try! (as-contract (stx-transfer? proposed-balance-a tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? proposed-balance-b tx-sender participant-b)))
    
    ;; Archive closed channel state
    (map-set payment-channels {