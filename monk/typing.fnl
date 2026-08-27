;; @module monk.typing
;; Symbol table with scope chains for the Monk compiler.
;; Walks AST and builds a stack of scopes where each scope maps
;; names to entity descriptors (kind, storage, type, fields, etc.)
(local fennel (require :fennel))

(local M {})

(var sym-table {})

; (let [(k v) (resolve-chain form)]
;   (set scope-tree k v))

(fn scoper [old new]
  (case old
    "" new
    _ (table.concat [old new] ".")))

(macro in-scope [name ...]
  `(let [,name (scoper scope form.name)]
     (do
       ,...)))

(macro typer [forms scope]
  `(each [_# v# (ipairs ,forms)]
     (type-assign ,scope v#)))

(fn type-param [id t scope]
  (let [var-scope (scoper scope id)]
    (set (. sym-table var-scope) {:type :field :bind-type t})))

(macro type-id-type-pair [list new-scope]
  `(each [_# v# (ipairs ,list)]
     (let [[idv# tv#] v#
           id# (. idv# :id)
           t# (. tv# :id)]
       (type-param id# t# ,new-scope))))

(fn type-assign [scope form]
  (case form.tag
    :struct-def (in-scope new-scope
                          (set (. sym-table new-scope) {:type :struct})
                          (type-id-type-pair form.fields new-scope))
    :enum-def (in-scope new-scope (set (. sym-table new-scope) {:type :enum})
                        (each [_ v (ipairs form.variants)]
                          (let [variant (scoper new-scope v.id)]
                            (set (. sym-table variant) {:type :variant}))))
    :fn-def (in-scope new-scope
                      (set (. sym-table new-scope)
                           {:type :fn :return-type form.return-type.id})
                      (type-id-type-pair form.params new-scope)
                      (typer form.body new-scope))
    :box/mut-def (in-scope new-scope
                           (set (. sym-table new-scope)
                                {:type :box-mut :bind-type form.type.id}))
    :box-def (in-scope new-scope
                       (set (. sym-table new-scope)
                            {:type :box :bind-type form.type.id}))
    :val-def (in-scope new-scope
                       (set (. sym-table new-scope)
                            {:type :val :bind-type form.type.id}))
    _ (do
        (print (fennel.view form))
        (print (.. "not implemented yet " form.tag)))))

(fn M.typing-pass [forms]
  (typer forms "")
  sym-table)

(fn M.dump-symtab [chains]
  (print (fennel.view chains)))

M
