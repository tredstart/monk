#lang racket

(require "ast.rkt")

(define data-list '())

(define global-res-counter 0)

(define (escape-qbe-string s)
  (list->string
   (let loop ([chars (string->list s)])
     (match chars
       ['() '()]
       [(cons #\\ rest) (cons #\\ (cons #\\ (loop rest)))]
       [(cons #\" rest) (cons #\\ (cons #\" (loop rest)))]
       [(cons #\newline rest) (append '(#\\ #\n) (loop rest))]
       [(cons #\tab rest) (append '(#\\ #\t) (loop rest))]
       [(cons c rest) (cons c (loop rest))]))))

(define (data-acc lst acc)
  (match lst
    ['() acc]
    [(cons
       (cons def content)
       tail)
     (data-acc tail (format "~adata $~a = { b \"~a\", b 0 }\n"
                             acc def (escape-qbe-string content)))]))

(define (emit-params params)
  (match params
    ['() ""]))

(define (emit-string-lit content)
  (define str (format "str~a" (length data-list)))
  (set! data-list (append data-list (list (cons str content))))
  (format "$~a" str))


(define (emit-args args res)
  (define inner-code "")
  (define pieces
    (for/list ([arg args])
      (define-values (code piece) (emit-arg arg res))
      (set! inner-code (string-append inner-code code))
      piece))
  (values inner-code (string-join pieces ", ")))


(define (emit-arg arg res)
  (match arg
    [(atom id)
     (values "" (format "w %~a" id))]
    [(string-lit content)
     (values "" (format "l ~a" (emit-string-lit content)))]
    [(int-lit val)
     (values "" (format "w ~a" val))]
    [(form 'idx args)
     (emit-field-access args)]
    [(form _ _)
     (values (string-append (emit-instruction arg) "\n")
             (format "w ~a" res))]
    [_ (raise-arguments-error
         'bad-argument-in-a-call
         "missing or unknown type of the argument: "
         (format "~a" arg))]))

(define (get-field-offset f)
  "so this should be a typesystem resolved but 
  to get bootstrap going let's try this way first"
  ;; (string->number (int-lit-value f)))
  (int-lit-value f))

(define (emit-field-access args)
  (match args
    [(list arg f)
     (let [(arg-name (format "%~a" (atom-id arg)))
           (f-name (format "%~a.~a" (atom-id arg) (int-lit-value f)))]
       (values
         (format
           "\n\t~a =l add ~a, ~a\n\t%ld =l loadl ~a\n"
           f-name arg-name (* 8 (get-field-offset f))
           f-name) ; <- temp solution
         (format "l %ld")))]
    [_ (raise-arguments-error 'not-enough-args "cannot access no name field")]))

(define (emit-instruction node)
  (match node
    ['() ""]
    [(atom id)
     (format "\tret %~a" id)]
    [(fn-def name params body)
     (let* ([main? (equal? name 'main)]
            [sig (if main? "w %argc, l %argv" (emit-params params))]
            [preamble (if main?
                          "\tcall $bamm_init(w %argc, l %argv)"
                          "")])
       (format
         "export function w $~a(~a) {\n@start\n~a\n~a\n}"
         name sig preamble
         (string-join (map emit-instruction body) "\n")))]
    [(int-lit val)
     (format "\tret ~a" val)]
    [(form name args)
     (let [(res (format "%res~a" global-res-counter))]
       (set! global-res-counter (+ global-res-counter 1))
       (define-values (inner-code args-list) (emit-args args res))
       (format
         "~a\t~a =w call $~a(~a)"
         inner-code
         res
         name args-list))]))

(provide emit-instruction data-acc data-list emit-params emit-string-lit emit-args)
