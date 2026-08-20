#lang typed/racket

(require/typed "ast.rkt"
  [#:struct fn-def ([name : Symbol] [params : (Listof Any)] [body : (Listof Any)])]
  [#:struct struct-def ([name : Symbol] [fields : (Listof Any)])]
  [#:struct union-def ([name : Symbol] [variants : (Listof Any)])]
  [#:struct enum-def ([name : Symbol] [variants : (Listof Any)])]
  [#:struct box-def ([name : Symbol] [expr : Any])]
  [#:struct box/mut-def ([name : Symbol] [expr : Any])]
  [#:struct val-def ([name : Symbol] [expr : Any])]
  [#:struct let-def ([bindings : (Listof Any)] [body : (Listof Any)])]
  [#:struct let-mut-def ([bindings : (Listof Any)] [body : (Listof Any)])]
  [#:struct atom ([id : Symbol])]
  [#:struct form ([name : Symbol] [args : (Listof Any)])])

(define-type Kind (U 'fn 'type 'struct 'union 'enum 'package 'variable))
(define-type Storage (U 'value 'box 'box/mut 'n/a))
(define-type Signature (U 'alias 'handle 'value 'n/a))
(define-type Lifetime (U 'any (Listof String)))

(struct type-info
  ([type : Symbol]
   [lifetime : Lifetime])
  #:transparent)

(struct entity
  ([kind : Kind]
   [storage : Storage]
   [signature : Signature]
   [lifetime : Lifetime]
   [params : (U 'any (Listof type-info))]
   [returns : (U False type-info)]
   [t : (U False type-info)]
   [fields : (U False (HashTable Symbol entity))])
  #:transparent)

;; Symbol table: maps names to their entity descriptors
(define-type SymTab (Mutable-HashTable String entity))

(: populate-builtins (-> SymTab Void))
(define (populate-builtins symtab)
  (define type-ent (entity 'type 'n/a 'value 'any 'any #f #f #f))
  (hash-set! symtab ":int" type-ent)
  (hash-set! symtab ":float" type-ent)
  (hash-set! symtab ":string" type-ent)
  (hash-set! symtab ":bool" type-ent)
  (hash-set! symtab ":char" type-ent)
  (hash-set! symtab ":void" type-ent)
  (define fn-ent (entity 'fn 'n/a 'handle 'any 'any #f #f #f))
  (hash-set! symtab "+" fn-ent)
  (hash-set! symtab "-" fn-ent)
  (hash-set! symtab "*" fn-ent)
  (hash-set! symtab "/" fn-ent)
  (hash-set! symtab "<" fn-ent)
  (hash-set! symtab ">" fn-ent)
  (hash-set! symtab "=" fn-ent)
  (hash-set! symtab ">=" fn-ent)
  (hash-set! symtab "<=" fn-ent)
  (hash-set! symtab "!=" fn-ent)
  (hash-set! symtab "printf" fn-ent)
  (hash-set! symtab "puts" fn-ent)
  (hash-set! symtab "exit" fn-ent))

(: walk-exprs (-> (Listof Any) SymTab Integer Void))
(define (walk-exprs exprs symtab depth)
  (for ([expr (in-list exprs)])
    (walk expr symtab depth)))

(: walk (-> Any SymTab Integer Void))
(define (walk ast symtab depth)
  (match ast
    [(fn-def name params body)
     (hash-set! symtab (symbol->string name)
                (entity 'fn 'n/a 'handle 'any 'any #f #f #f))
     (walk-exprs body symtab (+ depth 1))]
    [(struct-def name fields)
     (hash-set! symtab (symbol->string name)
                (entity 'struct 'box 'value 'any 'any #f #f #f))]
    [(union-def name variants)
     (hash-set! symtab (symbol->string name)
                (entity 'union 'box 'value 'any 'any #f #f #f))]
    [(enum-def name variants)
     (hash-set! symtab (symbol->string name)
                (entity 'enum 'box 'value 'any 'any #f #f #f))]
    [(box-def name expr)
     (hash-set! symtab (symbol->string name)
                (entity 'variable 'box 'value 'any 'any #f #f #f))
     (walk expr symtab depth)]
    [(box/mut-def name expr)
     (hash-set! symtab (symbol->string name)
                (entity 'variable 'box/mut 'value 'any 'any #f #f #f))
     (walk expr symtab depth)]
    [(val-def name expr)
     (hash-set! symtab (symbol->string name)
                (entity 'variable 'value 'value 'any 'any #f #f #f))
     (walk expr symtab depth)]
    [(let-def bindings body)
     (walk-exprs body symtab (+ depth 1))]
    [(let-mut-def bindings body)
     (walk-exprs body symtab (+ depth 1))]
    [(form 'type (list (atom name) rest ...))
     (hash-set! symtab (symbol->string name)
                (entity 'type 'n/a 'alias 'any 'any #f #f #f))
     (walk-exprs rest symtab depth)]
    [(form name args)
     (walk-exprs args symtab depth)]
    [_ (void)]))

;; Pass 1: Typing — build symbol table from ASTs, tracking depth for scoping
(: typing-pass (-> (Listof Any) SymTab))
(define (typing-pass asts)
  (define symtab : SymTab (make-hash))
  (populate-builtins symtab)
  (for ([ast (in-list asts)])
    (walk ast symtab 0))
  symtab)

;; Pass 2: Region inference — annotate lifetimes in the symbol table
(: regioning-pass (-> (Listof Any) SymTab SymTab))
(define (regioning-pass asts symtab)
  symtab)

(: dump-symtab (-> SymTab String Void))
(define (dump-symtab symtab path)
  (displayln symtab)
  (with-output-to-file path #:exists 'replace
    (lambda ()
      (hash-for-each symtab
        (lambda (k v)
          (printf "~a:\t~v\n" k v))))))

(module+ main
  (require/typed "parse.rkt"
    [parse-file (-> String (Listof Any))])

  (define args (current-command-line-arguments))
  (when (< (vector-length args) 1)
    (eprintf "Usage: racket typing.rkt <file.mk>\n")
    (exit 1))

  (define filename (vector-ref args 0))
  (printf "== Typing pass ==\n")
  (printf "Parsing ~a...\n" filename)
  (define asts (parse-file filename))
  (printf "~a top-level forms\n" (length asts))
  (define symtab (typing-pass asts))
  (printf "~a symbols in symtab\n" (hash-count symtab))

  (define out-path (string-append filename ".ty"))
  (dump-symtab symtab out-path)
  (printf "Wrote symtab to ~a\n" out-path))

(provide
  (struct-out type-info)
  (struct-out entity)
  SymTab
  populate-builtins
  walk
  typing-pass
  regioning-pass
  dump-symtab)
