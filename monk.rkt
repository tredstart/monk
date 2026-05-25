#lang racket

(require "parse.rkt")

;; -- MAIN ---
(define args (current-command-line-arguments))

(when (zero? (vector-length args))
  (eprintf "Usage: racket monk.rkt <filename>\n")
  (exit 1))

(define filename (vector-ref args 0))

; step 1: split file into syntax objects
(define (parse-file filename)
  (call-with-input-file filename
    (lambda (port)
      (port-count-lines! port)
      (let loop ([acc '()])
        (define stx (read-syntax filename port))
        (if (eof-object? stx) (reverse acc)
            (loop (cons stx acc)))))))

; step 2: read line by line to build an ast
(match (parse-file filename)
  ['() (displayln "EOF")]
  [exprs (for-each (lambda (stx) (displayln (parse-expr stx))) exprs)])

; step 3: typing
; step 4: memory management
; step 5: code gen to qbe




