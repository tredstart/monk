;; @module monk.typing
;; Symbol table with scope chains for the Monk compiler.
;; Walks AST and builds a stack of scopes where each scope maps
;; names to entity descriptors (kind, storage, type, fields, etc.)
(local fennel (require :fennel))

(local M {})

(var sym-table {})


(fn resolve-chain [form]
  (values (. form :name) {}))

(var scope-tree {:globals {:printf {}}})

; (let [(k v) (resolve-chain form)]
;   (set scope-tree k v))

(fn M.typing-pass [forms])

(fn M.dump-symtab [chains]
  (print (fennel.view scope-tree)))

M
