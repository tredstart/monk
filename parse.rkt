#lang racket
(require syntax/parse)
(require "ast.rkt")


(define-syntax-class bracket-list
  (pattern (_ ...) #:fail-unless
           (equal? (syntax-property this-syntax 'paren-shape) #\[)
           "lists must use '[' ']'"))
(define-syntax-class brace-list
  (pattern (_ ...) #:when (equal? (syntax-property this-syntax 'paren-shape) #\{)))

(define (syntax->string stx)
  (symbol->string (syntax->datum stx)))

(define-syntax-class type-decl
  (pattern type:id #:when (string-prefix? (syntax->string #'type) ":")))

(define (parse-params stx-list)
  (syntax-parse stx-list
    [() '()]
    [(name:id type:type-decl more ...)
     (list* (atom (syntax->datum #'name))
            (type-ref (syntax->datum #'type))
            (parse-params #'(more ...)))]
    [(type:type-decl . _) (raise-syntax-error
                            'no-parameter
                            "no parameter in the parameter list for this type"
                            (syntax->datum #'type))]
    [(name:id . _) (raise-syntax-error
                     'no-type
                     "missing type for a declared parameter"
                     (syntax->datum #'name))]))

(define (parse-let-bindings stx)
  (syntax-parse stx
    [() '()]
    [(name:id init:expr)
     (list (atom (syntax->datum #'name))
           (parse-expr #'init))]
    [(name:id init:expr more ...+)
     (list* (atom
              (syntax->datum #'name))
            (parse-expr #'init)
            (parse-let-bindings #'(more ...)))]))

(define (parse-expr stx)
  (syntax-parse stx
    #:datum-literals (fn struct mut immut macro union
                         enum type let let-mut)
    [x:id (atom (syntax->datum #'x))]
    [x:number (float-lit (syntax->datum #'x))]
    [x:integer (int-lit (syntax->datum #'x))]
    [x:string (string-lit (syntax->datum #'x))]
    [(immut ~! name:id expression:expr)
     (immut-def
       (syntax->datum #'name)
       (parse-expr #'expression))]

    [(mut ~! name:id expression:expr)
     (mut-def
       (syntax->datum #'name)
       (parse-expr #'expression))]
    [(let ~! bindings:bracket-list body:expr ...)
     (let-def (parse-let-bindings
                #'bindings)
              (map parse-expr
                   (syntax->list #'(body ...))))]

    [(let-mut ~! bindings:bracket-list body:expr ...)
     (let-mut-def (parse-let-bindings
                    #'bindings)
                  (map parse-expr
                       (syntax->list #'(body ...))))]

    [(struct ~! name:id fields:brace-list ...+)
     (struct-def
       (syntax->datum #'name)
       (map parse-params (syntax->list #'(fields ...))))]

    [(union ~! name:id fields:brace-list ...+)
     (union-def
       (syntax->datum #'name)
       (map parse-params (syntax->list #'(fields ...))))]

    [(enum ~! name:id variants:bracket-list)
     (enum-def
       (syntax->datum #'name)
       (map parse-expr (syntax->list #'variants)))]
    [(fn ~! name:id params:bracket-list body:expr ...)
     (fn-def
       (syntax->datum #'name)
       (parse-params (syntax->list #'params))
       (map parse-expr (syntax->list #'(body ...))))]
    [(name:id args:expr ...)
     (form
       (syntax->datum #'name)
       (map parse-expr (syntax->list #'(args ...))))]
    [wut (raise-syntax-error 'parse-error
                             (format "how? HOW? What is ~a?"
                                     (syntax->datum #'wut)) stx)]))

(provide parse-expr)
