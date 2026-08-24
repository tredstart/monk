(local fennel (require :fennel))
(local reader (require :monk.reader))
(local ast (require :monk.ast))
(local M {})

(local ops {:< :csltl
            :> :csgtl
            := :ceql
            :>= :csgel
            :<= :cslel
            :!= :cnel
            :i32->i64 :extsw
            :+ :add
            :* :mul
            :- :sub
            :/ :div})

;; @function die-at
;; @param x table the token or form carrying the position
;; @param msg string
(fn die-at [x msg]
  (error (.. msg " at line " (. x :line) ", col " (. x :col))))

;; @function sym?
;; @param x table|nil
(fn sym? [x]
  (= (. x :tag) :sym))

;; @function list?
;; @param x table
(fn list? [x]
  (= (. x :tag) :list))

(fn str? [x]
  (= (. x :tag) :str))

;; @function parse-token
;; @param x table reader token
;; @return table AST node
(fn parse-token [x]
  (case (. x :tag)
    :int (ast.int-lit x.val)
    :float (ast.float-lit x.val)
    :str (ast.string-lit x.val)
    :char (ast.char-lit x.val)
    :sym (if (= x.str :true) (ast.bool-def true)
             (= x.str :false) (ast.bool-def false)
             (ast.atom x.str))
    _ (die-at x (.. "how? HOW? What is " (. x :tag) "?"))))

;; @function prefix-sym?
;; @param x table|nil
;; @param p string single char prefix
(fn prefix-sym? [x prefix]
  (and (sym? x) (= (x.str:sub 1 1) prefix)))

;; @function shape-items
;; @param x table the form
;; @param shape keyword
;; @param msg string
(fn shape-items? [x shape msg]
  (print :SHAPE! (fennel.view x))
  (if (= (. x :shape) shape)
      (do
        (print "END OF SEQ")
        (. x :items))
      (die-at x msg)))

;; @function expect-sym
;; @param x table|nil the token to check
;; @param pos table the form carrying the position for errors
;; @param msg string
(fn expect-sym! [x pos msg]
  (if (sym? x) (. x :str) (die-at pos msg)))

(fn expect-type! [x pos msg]
  (when (not (sym? x)) (die-at pos msg))
  (when (prefix-sym? x ":")
    (ast.type-ref (x.str:sub 2))))

(fn expect-str! [x pos msg]
  (if (str? x) (. x :val) (die-at pos msg)))

;; @function M.parse-params
;; @param items list of reader tokens
;; @return list of [atom type-ref] pairs
(fn M.parse-params [items]
  (fcollect [i 1 (length items) 2]
    (let [name (. items i)
          sanity-name (expect-type! name)
          expected-ty (. items (+ i 1))
          t (expect-type! expected-ty)]
      (case [name sanity-name t]
        [name nil t] [(ast.atom (. name :str)) t]
        [name nil nil] (die-at name "missing type for a declared parameter")
        _ (die-at name "no parameter found")))))

;; @function M.parse-bound
;; @param x table reader form
;; @param tag keyword the box-def/box/mut-def/val-def constructor
;; @return table AST node
(fn M.parse-bound [x tag]
  (let [items (. x :items)]
    (if (= (length items) 4) ; Fennel quirk: . resolves the fn name by the tag
        ((. ast tag) (expect-sym! (. items 2) x "expected a name")
                     (expect-type! (. items 3) x "expected a type")
                     (M.parse-expr (. items 4)))
        (die-at x "box/box/mut/val expect a name, type and an expression"))))

;; @function M.parse-let-bindings
;; @param items list of reader tokens
;; @return list of [atom expr] pairs
(fn M.parse-let-bindings [items]
  (fcollect [i 1 (length items) 2]
    (let [name (. items i)
          init (. items (+ i 1))]
      (if (and (sym? name) init)
          [(ast.atom (. name :str)) (M.parse-expr init)]
          (die-at name "expected 'name expr' pairs in let bindings")))))

;; @function M.parse-cond-arm
;; @param arm table reader bracket form
;; @return table AST node
(fn M.parse-cond-arm [arm]
  (let [items (shape-items? arm :bracket "cond arms must use '[' ']'")
        cond (. items 1)
        bodies (fcollect [i 2 (length items)] (M.parse-expr (. items i)))]
    (if (prefix-sym? cond "_") (ast.cond-arm (ast.atom (. cond :str)) bodies)
        (list? cond) (ast.cond-arm (M.parse-expr cond) bodies)
        true (die-at arm
                     "Invalid condition. Maybe you've missed some ()? Or _ to mark this arm a wildcard?"))))

;; @function M.parse-match-arm
;; @param arm table reader bracket form
;; @return table AST node
(fn M.parse-match-arm [arm]
  (let [items (shape-items? arm :bracket "match arms must use '[' ']'")
        pattern (. items 1)
        bodies (fcollect [i 2 (length items)] (M.parse-expr (. items i)))]
    (if (prefix-sym? pattern "_")
        (ast.match-arm (ast.atom (. pattern :str)) bodies)
        (and (list? pattern) (prefix-sym? (. pattern.items 1) ".")
             (sym? (. pattern.items 2)) (= (length pattern.items) 2))
        (ast.match-arm (ast.union-variant (. pattern.items 1 :str)
                                          (. pattern.items 2 :str))
                       bodies)
        (prefix-sym? pattern ".")
        (ast.match-arm (ast.enum-variant (. pattern :str)) bodies)
        (= (. pattern :tag) :int)
        (ast.match-arm (ast.int-lit (. pattern :val)) bodies)
        (= (. pattern :tag) :float)
        (ast.match-arm (ast.float-lit (. pattern :val)) bodies)
        true
        (die-at arm "Invalid condition. Maybe _ to mark this arm a wildcard?"))))

;; @function M.parse-expr
;; @param x table reader token or form
;; @return table AST node
(fn M.parse-expr [x]
  (if (not (list? x))
      (parse-token x)
      (let [items (. x :items)
            head (. items 1)
            form-call (and (sym? head) (. head :str))]
        (print "items: " (fennel.view items))
        (if (not form-call)
            (die-at x "expected a symbol to open a form")
            (case form-call
              :package (ast.package (expect-str! (. items 2) x
                                                 "Expected a package name"))
              :box (M.parse-bound x :box-def)
              :box/mut (M.parse-bound x :box/mut-def)
              :val (M.parse-bound x :val-def)
              :fn (ast.fn-def (expect-sym! (. items 2) x
                                           "expected a function name")
                              (M.parse-params (shape-items? (. items 3)
                                                            :bracket
                                                            "lists must use '[' ']'"))
                              (expect-type! (. items 4) x
                                            "expected a return type!")
                              (fcollect [i 5 (length items)]
                                (M.parse-expr (. items i))))
              :struct (ast.struct-def (expect-sym! (. items 2) x
                                                   "expected a type name")
                                      (M.parse-params (shape-items? (. items 3)
                                                                    :brace
                                                                    "fields/map definitions must use '{' '}'")))
              :union (ast.union-def (expect-sym! (. items 2) x
                                                 "expected a type name")
                                    (M.parse-params (shape-items? (. items 3)
                                                                  :brace
                                                                  "fields/map definitions must use '{' '}'")))
              :enum (ast.enum-def (expect-sym! (. items 2) x
                                               "expected a type name")
                                  (icollect [_ v (ipairs (shape-items? (. items
                                                                          3)
                                                                       :bracket
                                                                       "lists must use '[' ']'"))]
                                    (M.parse-expr v)))
              :let (ast.let-def (M.parse-let-bindings (shape-items? (. items 2)
                                                                    :bracket
                                                                    "lists must use '[' ']'"))
                                (fcollect [i 3 (length items)]
                                  (M.parse-expr (. items i))))
              :let-mut (ast.let-mut-def (M.parse-let-bindings (shape-items? (. items
                                                                               2)
                                                                            :bracket
                                                                            "lists must use '[' ']'"))
                                        (fcollect [i 3 (length items)]
                                          (M.parse-expr (. items i))))
              :cond (ast.cond-expr (fcollect [i 2 (length items)]
                                     (M.parse-cond-arm (. items i))))
              :match (ast.match-expr (ast.atom (expect-sym! (. items 2) x
                                                            "expected a match target"))
                                     (fcollect [i 3 (length items)]
                                       (M.parse-match-arm (. items i))))
              _ (ast.form (or (. ops form-call) form-call)
                          (fcollect [i 2 (length items)]
                            (M.parse-expr (. items i)))))))))

;; @function M.parse-file
;; @param filename string
;; @return list of AST nodes
(fn M.parse-file [filename]
  (let [src (reader.read-file filename)]
    (fcollect [i 1 (length src)] (M.parse-expr (. src i)))))

M
