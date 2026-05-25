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


;; (define (parse-params stx))

(define (parse-expr stx)
  (syntax-parse stx
    #:datum-literals (fn struct mut immut macro union
                         enum type let let-mut)
    [x:id (atom (syntax->datum #'x))]
    [x:number (float-lit (syntax->datum #'x))]
    [x:integer (int-lit (syntax->datum #'x))]
    [x:string (string-lit (syntax->datum #'x))]
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
