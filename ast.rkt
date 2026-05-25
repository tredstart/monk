#lang racket

;; literals
(struct atom (id) #:transparent)
(struct int-lit (value) #:transparent)
(struct float-lit (value) #:transparent)
(struct string-lit (content) #:transparent)
(struct char-lit (ch) #:transparent)
(struct type-ref (id) #:transparent)

; field access
; alice.age, core.print
; core.print
(struct field-access (target field) #:transparent)

; type/struct/union/enum
(struct struct-def (name fields) #:transparent)
(struct union-def (name variants) #:transparent)
; variants = list of struct/union-field
(struct enum-def (name variants) #:transparent)
; variants = list of symbols
(struct enum-variant (name) #:transparent)


(struct immut-def (name expr) #:transparent)
(struct mut-def (name expr) #:transparent)
(struct bool-def (id) #:transparent)

; function definition
(struct fn-def (name params body) #:transparent)
;;
;; (struct pat-wildcard () #:transparent) ; _
;; (struct pat-binding (name) #:transparent) ; v  — fresh name binding
;; (struct pat-literal (value) #:transparent) ; 0, 1, "str"
;; (struct pat-none () #:transparent) ; none
;; (struct pat-enum-variant (variant) #:transparent) ; .north
;; (struct pat-union-payload (variant binding) #:transparent) ; (.circle r)
; variant = symbol, binding = symbol (the destructured payload name)

(struct match-arm (pattern expr) #:transparent)
(struct match-expr (target arms) #:transparent)

(struct cond-arm (condition expr) #:transparent) ; condition = expr or wildcard
(struct cond-expr (arms) #:transparent) ; arms = list of cond-arm

; let forms
(struct let-def (bindings body) #:transparent)
(struct let-mut-def (bindings body) #:transparent)

; generic form
(struct form (name args) #:transparent)

; provides

(provide
  (struct-out atom)
  (struct-out int-lit)
  (struct-out float-lit)
  (struct-out string-lit)
  (struct-out bool-def)
  (struct-out type-ref)

  (struct-out field-access)

  (struct-out struct-def)
  (struct-out union-def)
  (struct-out enum-def)

  (struct-out immut-def)
  (struct-out mut-def)

  (struct-out fn-def)

  ;;
  ;; (struct-out pat-wildcard)
  ;; (struct-out pat-binding)
  ;; (struct-out pat-literal)
  ;; (struct-out pat-none)
  ;; (struct-out pat-enum-variant)
  ;; (struct-out pat-union-payload)
  (struct-out match-arm)
  (struct-out match-expr)

  (struct-out cond-arm)
  (struct-out cond-expr)

  (struct-out let-def)
  (struct-out let-mut-def)
  (struct-out char-lit)

  ;; (struct-out for-loop)

  (struct-out form)
  (struct-out enum-variant))
