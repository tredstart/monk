#lang racket

(require "ast.rkt")

(define program "")

(define data-list '())

(define (data-acc lst acc)
  (match lst
    ['() acc]
    [(cons
       (cons def content)
       tail)
     (data-acc tail (format "~adata ~a = { b \"~a\", b 0 }\n"
                            acc def (escape-qbe-string content)))]))

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


(struct ctx
  ([result-count #:mutable]
   [condition-count #:mutable]
   [loop-count #:mutable]))

(define (ret-val func lst)
  (match lst
    ['() 0]
    [(list x) (func x)]
    [(cons x xs) (begin
                   (func x)
                   (ret-val func xs))]))

(define globals
  (hash
    'csltl "" 'csgtl "" 'ceql "" 'cnel "" 'csgel "" 'cslel ""
    'add "" 'mul "" 'sub "" 'div ""))

(define (emit-instruction node context)
  (match node
    [(atom id) (format "%~a" id)]
    [(int-lit value) (format "~a" value)]
    [(float-lit value) value]
    [(string-lit content)
     (let [(str (format "$str~a" (length data-list)))]
       (set! data-list
             (append data-list (list (cons str content))))
       str)]

    [(form 'idx args)
     ; make it only for not nested for now
     (match args
       [(list n index)
        (set-ctx-result-count! context (+ (ctx-result-count context) 1))
        (define access-result (format "%r~a" (ctx-result-count context)))

        (set-ctx-result-count! context (+ (ctx-result-count context) 1))
        (define inter-result (format "%r~a" (ctx-result-count context)))
        (let [(result (* 8 (string->number (emit-instruction index context))))
              (name (emit-instruction n context))]
          (set! program
                (string-append program
                               (format "\t~a =l add ~a, ~a\n\t~a =l loadl ~a\n"
                                       access-result name result
                                       inter-result access-result)))
          inter-result)])]
    [(form 'set (cons (atom name) value))
     (define result (ret-val (lambda (x) (emit-instruction x context)) value))
     (set! program
           (string-append program
                          (format "\tstorel ~a, %~a\n"
                                  result name)))]

    [(form name args) #:when (hash-has-key? globals name)
     (define sum
       (map (lambda (x)
              (emit-instruction x context)) args))
     (define args-list (string-join sum ", "))
     (set-ctx-result-count! context (+ (ctx-result-count context) 1))
     (define result (format "%r~a" (ctx-result-count context)))
     (set! program
           (string-append program
                          (format "\t~a =l ~a ~a\n" result name args-list)))
     result]

    [(immut-def name expr)
     (let [(expr-res (emit-instruction expr context))]
       (set! program
             (string-append program (format "\t%~a =l copy ~a\n" name expr-res))))]
    ;; temprorarily this will affect nothing actually
    [(mut-def name expr)
     (let [(expr-res (emit-instruction expr context))]
       (set! program
             (string-append program
                            (format
                              "\t%~a =l alloc8 8\n\tstorel ~a, %~a\n"
                              name expr-res name))))]

    [(bool-def id)
     (match id
       ('true 1)
       ('false 0)
       (_
         (raise-contract-error
           'third-boolean-provided "somehow it got parsed as a bool")))]
    [(fn-def 'main _ body)
     (set! program
           (string-append program
                          "export function l $main(l %argc, l %argv){\n"
                          "@start\n"
                          "\tcall $bamm_init(l %argc, l %argv)\n"))
     (define ret (ret-val (lambda (x)
                            (emit-instruction x context)) body))
     (set! program
           (string-append program
                          (format "\tret ~a\n}\n" ret)))]
    [(fn-def name params body)
     ;; this is temp due to missing logic on the reversing
     ;; atom - type-re => type-ref atom
     (let [(param-list (string-join
                         (map
                           (lambda (item)
                             (match item
                               ['() ""]
                               [(atom _) ""]
                               [(type-ref _) ""])) params) ", "))]
       (set! program
             (string-append program
                            (format "function l $~a(~a){\n@start\n"
                                    name param-list)))
       (define ret (ret-val (lambda (x)
                              (emit-instruction x context)) body))
       (set! program
             (string-append program
                            (format "\tret ~a\n}\n" ret))))]
    [(form 'deref (list (atom name)))
     (set-ctx-result-count! context (+ (ctx-result-count context) 1))
     (define result (format "%r~a" (ctx-result-count context)))
     (set! program
           (string-append program (format "\t~a =l loadl %~a\n" result name)))
     result]
    [(form 'while args)
     (define label (format "@loop~a" (ctx-loop-count context)))

     (set-ctx-loop-count! context (+ (ctx-loop-count context) 1))
     (set! program (string-append program (format "~a\n" label)))
     (match args
       [(cons condition body)
        (define result (emit-instruction condition context))
        (set! program
              (string-append program
                             (format "\tjnz ~a, ~a.body, ~a.end\n~a.body\n"
                                     result label label label)))
        (map (lambda (x) (emit-instruction x context)) body)
        (set! program
              (string-append program
                             (format "\tjmp ~a\n~a.end\n"
                                     label label)))]
       [_ (raise-syntax-error 'missing-body "there is no body in the while" args)])]
    [(form name args)
     (define sum
       (map (lambda (x)
              (string-append "l "
                             (emit-instruction x context))) args))
     (define args-list (string-join sum ", "))

     (set-ctx-result-count! context (+ (ctx-result-count context) 1))
     (define result (format "%r~a" (ctx-result-count context)))
     (set! program
           (string-append program
                          (format "\t~a =l call $~a(~a)\n"
                                  result name args-list)))
     result]
    [(cond-expr arms)
     (define label (format "@cond~a" (ctx-condition-count context)))

     (set-ctx-condition-count! context (+ (ctx-condition-count context) 1))

     (set! program (string-append program (format "~a\n" label)))
     (emit-cond-arm arms label context 0)
     (set! program (string-append program (format "~a.end\n" label)))]
    [form (raise-syntax-error 'bad-syntax-i-guess
                              "could not figure out what to emit"
                              form)]))

(define (emit-cond-arm arms label context counter)
  (set! program
        (string-append program (format "~a.body~a\n" label counter)))
  (match arms
    ['() ""]
    [(cons (cond-arm condition body) rst)
     (set! counter (+ counter 1))
     (set-ctx-result-count! context (+ (ctx-result-count context) 1))
     (define res (emit-instruction condition context))
     (define body-label (format "~a.body~a" label counter))
     (define else-label (format "~a.body~a" label (+ counter 1)))
     (set! program
           (string-append program
                          (format
                            "\tjnz ~a, ~a, ~a\n~a\n"
                            res body-label else-label body-label)))
     (map (lambda (x) (emit-instruction x context)) body)

     (set! program
           (string-append program
                          (format "\tjmp ~a.end\n" label)))
     (emit-cond-arm rst label context (+ counter 1))]))

(provide program data-acc emit-instruction data-list (struct-out ctx))
