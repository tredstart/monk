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
      (define-values (piece code) (emit-arg arg res))
      (set! inner-code (string-append inner-code code))
      piece))
  (values (string-join pieces ", ") inner-code))

(define (emit-arg arg res)
  (match arg
    [(atom id)
     (values (format "%~a" id) "")]
    [(string-lit content)
     (values (emit-string-lit content) "")]
    [(int-lit val)
     (values (format "~a" val) "")]
    [(form 'idx args)
     (emit-field-access args)]
    [(form _ _)
     (define-values (_ s) (emit-instruction arg))
     (values (format "%~a" res) (string-append s "\n"))]
    [_ (raise-arguments-error
         'bad-argument-in-a-call
         "missing or unknown type of the argument: "
         (format "~a" arg))]))

(define (get-field-offset f)
  "so this should be a typesystem resolved but 
  to get bootstrap going let's try this way first"
  ;; (string->number (int-lit-value f)))
  (int-lit-value f))

(define globals
  (hash
    'csltw ""
    'csgtw ""
    'ceqw ""
    'cnew ""
    'csgew ""
    'cslew ""
    'add ""
    'mul ""
    'sub ""
    'div ""
    ))

(define (emit-field-access args)
  (match args
    [(list arg f)
     (let [(arg-name (format "%~a" (atom-id arg)))
           (f-name (format "%~a.~a" (atom-id arg) (int-lit-value f)))]
       (values
         "%ld"
         (format
           "\n\t~a =l add ~a, ~a\n\t%ld =l loadl ~a\n"
           f-name arg-name (* 8 (get-field-offset f))
           f-name)))]
    [_ (raise-arguments-error 'not-enough-args "cannot access no name field")]))

(define cond-counter 0)
(define cond-body-counter 0)

(define (emit-condition-resolution branch)
  (define branch-id (format "@c~a.cond~a" cond-counter cond-counter))
  (set! cond-counter (+ cond-counter 1))
  (define-values (res condition) (emit-instruction branch))
  (values res (format "~a\n~a" condition branch-id)))

;; one cond arm should translate into
;; %c1 =l __ a1, a2
;; %c2 =l __ a1, a2
;; @c1.cond1
;;   jnz %c1 @c1.body1 @c1.cond2 <- if we have a next one
;; @c1.cond2
;;   jnz %c2 @c1.body2 @else
;; @c1.body1
;;   do some work here
;; @c1.body2
;;   do some work here
;; @else
;; # either body if _ or empty

(define (emit-instruction node)
  (match node
    ['() (values "" "")]
    [(atom id)
     (values id (format "\tret %~a" id))]
    [(fn-def name params body)
     (let* ([main? (equal? name 'main)]
            [sig (if main? "w %argc, l %argv" (emit-params params))]
            [preamble (if main?
                          "\tcall $bamm_init(w %argc, l %argv)"
                          "")])
       (values "" (format
                    "export function w $~a(~a) {\n@start\n~a\n~a\n}"
                    name sig preamble
                    (string-join (map
                                   (lambda (x)
                                     (define-values (_ c)
                                       (emit-instruction x))
                                     c)
                                   body) "\n"))))]
    [(int-lit val)
     (values val (format "\tret ~a" val))]

    [(form 'idx args)
     (emit-field-access args)]
    [(form name args)
     (let [(res (format "%res~a" global-res-counter))]
       (set! global-res-counter (+ global-res-counter 1))
       (define-values (args-list inner-code) (emit-args args res))
       (define result (format
                        "~a\t~a =l "
                        inner-code
                        res))
       (define call
         (match name
           [(? (lambda (k) (hash-has-key? globals k)))
            (format "~a ~a\n" name args-list)]
           [_
            (define (add-type a)
              (if (string-prefix? a "$")
                  (format "l ~a" a)
                  (format "w ~a" a)))
            (format "call $~a(~a)\n"
                    name
                    (string-join (map add-type (string-split args-list ", ")) ", "))]))
       (values res (string-append result call)))]

    [(immut-def name expr)
     (let [(v (format "%~a" name))]
       (define-values (r code) (emit-instruction expr))
       (when (string-prefix? code "\tret") (set! code ""))
       (values r
               (format
                 "~a\t~a =l copy ~a"
                 code
                 v r)))]


    [(cond-expr arms)
     (define else-cond (format "\n@else~a\n" (+ cond-counter 1)))
     (values ""
             (string-append
               (string-join
                 (map
                   (lambda (arm)
                     (match arm
                       [(cond-arm condition body)
                        (define bd (format "@body~a" cond-body-counter))
                        (set! cond-body-counter (+ cond-body-counter 1))
                        (define-values
                          (res c)
                          (emit-condition-resolution condition))
                        (string-append c (format
                                           "\n\tjnz ~a, ~a, @else~a\n~a\n~a\n"
                                           res
                                           bd
                                           cond-counter
                                           bd
                                           (string-join
                                             (map
                                               (lambda (x)
                                                 (define-values
                                                   (_ r)
                                                   (emit-instruction x))
                                                 r)
                                               body)
                                             "\n"

                                             )))]
                       [(cond-arm (atom 'wildcard) _) (format "@else~a\n" cond-counter)] ; body resolution again

                       ))
                   arms) "\n")
               else-cond))]))

(provide emit-instruction data-acc data-list emit-params emit-string-lit emit-args)
