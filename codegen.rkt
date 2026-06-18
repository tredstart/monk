#lang racket

(require "ast.rkt")

(define data-list '())


(define (data-acc lst acc)
  (match lst
    ['() acc]
    [(cons
       (cons def content)
       tail)
     (data-acc tail (format "~adata $~a = { b \"~a\", b 0 }"
                            acc def content))]))

(define (emit-params params)
  (match params
    ['() ""]))

(define (emit-string-lit content)
  (define str (format "str~a" (length data-list)))
  (set! data-list (append data-list (list (cons str content))))
  (format "$~a" str))


(define (emit-args args)
  (string-join (map emit-arg args) ", "))

(define (emit-arg arg)
  (match arg
    [(string-lit content)
     (format "l ~a" (emit-string-lit content))]
    [(int-lit val)
     (format "w ~a" val)]
    [_ ""]))

(define (emit-instruction node)
  (match node
    ['() ""]
    [(atom id)
     (format "\tret ~a" id)]
    [(fn-def name params body)
     (format
       "export function w $~a(~a) {\n@start\n~a\n}"
       name (emit-params params)
       (string-join (map emit-instruction body) "\n"))]
    [(int-lit val)
     (format "\tret ~a" val)]
    [(form name args)
     (format
       "\t%r =w call $~a(~a)" name (emit-args args))]))

(provide emit-instruction data-acc data-list emit-params emit-string-lit emit-args)
