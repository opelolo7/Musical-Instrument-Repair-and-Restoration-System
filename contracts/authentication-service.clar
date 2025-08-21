;; Musical Instrument Repair and Restoration - Authentication Service
;; Manages instrument authentication and value assessment

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INSTRUMENT-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-ALREADY-AUTHENTICATED (err u403))
(define-constant ERR-ASSESSMENT-NOT-FOUND (err u404))

;; Authentication status constants
(define-constant STATUS-PENDING "pending")
(define-constant STATUS-AUTHENTICATED "authenticated")
(define-constant STATUS-DISPUTED "disputed")
(define-constant STATUS-REJECTED "rejected")

;; Data Variables
(define-data-var next-instrument-id uint u1)
(define-data-var next-assessment-id uint u1)

;; Data Maps
(define-map instrument-records
  { id: uint }
  {
    owner: principal,
    instrument-type: (string-ascii 50),
    maker: (string-ascii 100),
    year-made: uint,
    serial-number: (string-ascii 50),
    authenticity-status: (string-ascii 20),
    provenance: (string-ascii 500),
    condition-rating: uint,
    assessed-value: uint,
    certificate-hash: (buff 32),
    authenticator: (optional principal),
    authentication-date: (optional uint),
    created-at: uint
  }
)

(define-map value-assessments
  { id: uint }
  {
    instrument-id: uint,
    assessor: principal,
    market-value: uint,
    insurance-value: uint,
    condition-factors: (list 5 (string-ascii 100)),
    comparable-sales: (list 3 uint),
    assessment-notes: (string-ascii 500),
    valid-until: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map authentication-history
  { instrument-id: uint, entry: uint }
  {
    action: (string-ascii 50),
    performer: principal,
    details: (string-ascii 300),
    timestamp: uint,
    previous-status: (string-ascii 20),
    new-status: (string-ascii 20)
  }
)

(define-map authorized-authenticators
  { authenticator: principal }
  {
    name: (string-ascii 100),
    specializations: (list 5 (string-ascii 50)),
    credentials: (string-ascii 300),
    reputation-score: uint,
    active: bool,
    authorized-by: principal,
    authorization-date: uint
  }
)

;; Public Functions

;; Register instrument for authentication
(define-public (register-instrument
  (instrument-type (string-ascii 50))
  (maker (string-ascii 100))
  (year-made uint)
  (serial-number (string-ascii 50))
  (provenance (string-ascii 500)))
  (let ((instrument-id (var-get next-instrument-id)))
    (asserts! (> (len instrument-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len maker) u0) ERR-INVALID-INPUT)
    (asserts! (> year-made u1600) ERR-INVALID-INPUT)
    (asserts! (< year-made u2025) ERR-INVALID-INPUT)

    (map-set instrument-records
      { id: instrument-id }
      {
        owner: tx-sender,
        instrument-type: instrument-type,
        maker: maker,
        year-made: year-made,
        serial-number: serial-number,
        authenticity-status: STATUS-PENDING,
        provenance: provenance,
        condition-rating: u0,
        assessed-value: u0,
        certificate-hash: 0x00,
        authenticator: none,
        authentication-date: none,
        created-at: block-height
      }
    )

    (var-set next-instrument-id (+ instrument-id u1))
    (ok instrument-id)
  )
)

;; Authenticate instrument
(define-public (authenticate-instrument
  (instrument-id uint)
  (condition-rating uint)
  (assessed-value uint)
  (certificate-hash (buff 32)))
  (let ((instrument (unwrap! (map-get? instrument-records { id: instrument-id }) ERR-INSTRUMENT-NOT-FOUND)))
    (asserts! (is-some (map-get? authorized-authenticators { authenticator: tx-sender })) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get authenticity-status instrument) STATUS-PENDING) ERR-ALREADY-AUTHENTICATED)
    (asserts! (<= condition-rating u10) ERR-INVALID-INPUT)
    (asserts! (> assessed-value u0) ERR-INVALID-INPUT)

    (map-set instrument-records
      { id: instrument-id }
      (merge instrument {
        authenticity-status: STATUS-AUTHENTICATED,
        condition-rating: condition-rating,
        assessed-value: assessed-value,
        certificate-hash: certificate-hash,
        authenticator: (some tx-sender),
        authentication-date: (some block-height)
      })
    )

    ;; Add to authentication history
    (map-set authentication-history
      { instrument-id: instrument-id, entry: u1 }
      {
        action: "authenticated",
        performer: tx-sender,
        details: "Instrument successfully authenticated",
        timestamp: block-height,
        previous-status: STATUS-PENDING,
        new-status: STATUS-AUTHENTICATED
      }
    )

    (ok true)
  )
)

;; Create value assessment
(define-public (create-assessment
  (instrument-id uint)
  (market-value uint)
  (insurance-value uint)
  (condition-factors (list 5 (string-ascii 100)))
  (comparable-sales (list 3 uint))
  (assessment-notes (string-ascii 500)))
  (let ((assessment-id (var-get next-assessment-id))
        (instrument (unwrap! (map-get? instrument-records { id: instrument-id }) ERR-INSTRUMENT-NOT-FOUND)))
    (asserts! (is-some (map-get? authorized-authenticators { authenticator: tx-sender })) ERR-NOT-AUTHORIZED)
    (asserts! (> market-value u0) ERR-INVALID-INPUT)
    (asserts! (>= insurance-value market-value) ERR-INVALID-INPUT)

    (map-set value-assessments
      { id: assessment-id }
      {
        instrument-id: instrument-id,
        assessor: tx-sender,
        market-value: market-value,
        insurance-value: insurance-value,
        condition-factors: condition-factors,
        comparable-sales: comparable-sales,
        assessment-notes: assessment-notes,
        valid-until: (+ block-height u52560), ;; ~1 year
        status: "active",
        created-at: block-height
      }
    )

    (var-set next-assessment-id (+ assessment-id u1))
    (ok assessment-id)
  )
)

;; Authorize authenticator
(define-public (authorize-authenticator
  (authenticator principal)
  (name (string-ascii 100))
  (specializations (list 5 (string-ascii 50)))
  (credentials (string-ascii 300)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len specializations) u0) ERR-INVALID-INPUT)

    (map-set authorized-authenticators
      { authenticator: authenticator }
      {
        name: name,
        specializations: specializations,
        credentials: credentials,
        reputation-score: u50,
        active: true,
        authorized-by: tx-sender,
        authorization-date: block-height
      }
    )
    (ok true)
  )
)

;; Dispute authentication
(define-public (dispute-authentication (instrument-id uint) (reason (string-ascii 300)))
  (let ((instrument (unwrap! (map-get? instrument-records { id: instrument-id }) ERR-INSTRUMENT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get owner instrument)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get authenticity-status instrument) STATUS-AUTHENTICATED) ERR-INVALID-INPUT)
    (asserts! (> (len reason) u0) ERR-INVALID-INPUT)

    (map-set instrument-records
      { id: instrument-id }
      (merge instrument { authenticity-status: STATUS-DISPUTED })
    )

    ;; Add to authentication history
    (map-set authentication-history
      { instrument-id: instrument-id, entry: u2 }
      {
        action: "disputed",
        performer: tx-sender,
        details: reason,
        timestamp: block-height,
        previous-status: STATUS-AUTHENTICATED,
        new-status: STATUS-DISPUTED
      }
    )

    (ok true)
  )
)

;; Update authenticator reputation
(define-public (update-authenticator-reputation (authenticator principal) (new-score uint))
  (let ((auth-record (unwrap! (map-get? authorized-authenticators { authenticator: authenticator }) ERR-NOT-AUTHORIZED)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u100) ERR-INVALID-INPUT)

    (map-set authorized-authenticators
      { authenticator: authenticator }
      (merge auth-record { reputation-score: new-score })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get instrument record
(define-read-only (get-instrument (instrument-id uint))
  (map-get? instrument-records { id: instrument-id })
)

;; Get value assessment
(define-read-only (get-assessment (assessment-id uint))
  (map-get? value-assessments { id: assessment-id })
)

;; Get authentication history entry
(define-read-only (get-history-entry (instrument-id uint) (entry uint))
  (map-get? authentication-history { instrument-id: instrument-id, entry: entry })
)

;; Get authenticator info
(define-read-only (get-authenticator (authenticator principal))
  (map-get? authorized-authenticators { authenticator: authenticator })
)

;; Check if authenticator is authorized
(define-read-only (is-authorized-authenticator (authenticator principal))
  (match (map-get? authorized-authenticators { authenticator: authenticator })
    auth-record (get active auth-record)
    false
  )
)

;; Check if assessment is valid
(define-read-only (is-assessment-valid (assessment-id uint))
  (match (map-get? value-assessments { id: assessment-id })
    assessment (and
                 (is-eq (get status assessment) "active")
                 (< block-height (get valid-until assessment)))
    false
  )
)

;; Get next instrument ID
(define-read-only (get-next-instrument-id)
  (var-get next-instrument-id)
)

;; Get next assessment ID
(define-read-only (get-next-assessment-id)
  (var-get next-assessment-id)
)
