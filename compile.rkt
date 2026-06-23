#lang racket

(require "parse.rkt")
(require "codegen.rkt")

; emit-program : (listof ast?) -> string
(define (emit-program asts)
  (values ""
          (string-append
            (match asts
              ['() ""]
              [(cons node _)
               (define-values (_ code) (emit-instruction node))
               code])
            "\n"
            (data-acc data-list ""))))

; Parse a .mk source file into a list of AST nodes.
(define (parse-file filename)
  (call-with-input-file filename
    (lambda (port)
      (port-count-lines! port)
      (let loop ([acc '()])
        (define stx (read-syntax filename port))
        (if (eof-object? stx)
            (reverse acc)
            (loop (cons (parse-expr stx) acc)))))))

; Compile a .mk file all the way to a native binary.
(define (compile-file filename [output-name #f])
  (define out-dir "bin")
  (system (format "mkdir -p ~a" out-dir))
  (define base (path->string
                 (build-path out-dir
                             (or output-name
                                 (path-replace-suffix
                                   (file-name-from-path (string->path filename))
                                   #"")))))

  ; Step 1 - Parse
  (printf "  [1/6] Parsing ~a...\n" filename)
  (define asts (parse-file filename))
  (printf "         ~a top-level form(s)\n" (length asts))

  ; Step 2 - Code generation: AST -> QBE IR text
  (printf "  [2/6] Generating QBE IR...\n")
  (define-values (_ ssa-text) (emit-program asts))
  (printf "         ~a bytes of QBE IR\n" (string-length ssa-text))

  ; Step 3 - Write the .ssa file
  (define ssa-path (string-append base ".ssa"))
  (printf "  [3/6] Writing ~a...\n" ssa-path)
  (with-output-to-file ssa-path #:exists 'replace
    (lambda () (display ssa-text)))

  ; Step 4 - QBE: .ssa -> .s (assembly)
  (define asm-path (string-append base ".s"))
  (printf "  [4/6] Running QBE (~a -> ~a)...\n" ssa-path asm-path)
  (unless (system (format "qbe -o ~a ~a" asm-path ssa-path))
    (eprintf "ERROR: QBE failed on ~a\n" ssa-path)
    (exit 1))

  ; Step 5 - Assembler: .s -> .o
  (define obj-path (string-append base ".o"))
  (printf "  [5/6] Assembling (~a -> ~a)...\n" asm-path obj-path)
  (unless (system (format "gcc -c -g -o ~a ~a" obj-path asm-path))
    (eprintf "ERROR: assembly failed on ~a\n" asm-path)
    (exit 1))

  ; Step 6 - Link: .o + runtime -> binary
  (define bin-path base)
  (printf "  [6/6] Linking with runtime (~a + runtime.c -> ~a)...\n" obj-path bin-path)
  (unless (system (format "gcc -g -o ~a ~a runtime.c" bin-path obj-path))
    (eprintf "ERROR: linking failed\n")
    (exit 1))

  (printf "\nCompiled: ~a\n" bin-path))

; CLI
(define args (current-command-line-arguments))
(define (parse-cli args-lst)
  (match args-lst
    [(list input) (values input #f)]
    [(list "-o" output input) (values input output)]
    [(list input "-o" output) (values input output)]
    [(list _ ...) (values #f #f)]))
(define-values (input output) (parse-cli (vector->list args)))
(cond
  [(not input)
   (eprintf "Usage: racket compile.rkt <file.mk> [-o <output>]\n")
   (exit 1)]
  [else
   (compile-file input output)])
