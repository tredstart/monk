;; @module monk.typing
;; Symbol table with scope chains for the Monk compiler.
;; Walks AST and builds a stack of scopes where each scope maps
;; names to entity descriptors (kind, storage, type, fields, etc.)
(local fennel (require :fennel))

(local M {})

; :parent.arena-b
; {:make-value {:params {:ctx :parent}
;               :return :parent
;               :body {:y :parent.arena-b}}}

(var a-table {})
(local ANY {})

(local in-new {:tag :form :name :in-new})
(local _in {:tag :fn-def :name :in})

(macro arena [context]
  `{:arena [(table.unpack ,context)]})

(fn return-exists [last-result variables]
  (and last-result (. variables last-result)))

(fn handle-fn [function]
  (local f (partial . a-table))
  (var last-result nil)
  (var im-context [])
  (var variables {})
  (each [_ p (ipairs function.params)]
    (let [param (. p 1)]
      (set (. variables param.id) (arena im-context))))
  (each [_ v (ipairs function.body)]
    (case v
      {:tag :form :name :in-new :args _} (let [arena-name (. (. v.args 1) :name)]
                                           (print "hit in-new")
                                           (table.insert im-context arena-name))
      (where {: tag :expr {:tag :form :name :new}}
             (or (= tag :box/mut-def) (= tag :box-def))) (do
                                                                 (print "hit definition")
                                                                 (set (. variables
                                                                         v.name)
                                                                      (arena im-context)))
      {:tag :atom : id} (do
                          (print "hit id")
                          (set last-result id))
      _ (print "looking at: " (fennel.view v))))
  (table.remove im-context)
  (let [re (return-exists last-result variables)
        le (length im-context)
        rle (if (and re re.arena) (length re.arena) 0)]
    (when (and re (> rle le))
      (let [node-name (or last-result :<unknown>)
            arena-path (table.concat (icollect [_ v (ipairs re.arena)]
                                       (if (= v ANY) :<any> (tostring v)))
                                     " -> ")]
        (error (string.format "Lifetime error: '%s' tries to escape context [%s]"
                              node-name arena-path))))))

(fn handle-form [form]
  (case form.tag :fn-def (handle-fn form)))

(fn M.sign-pass [forms]
  (each [_ v (ipairs forms)]
    (handle-form v))
  a-table)

M
