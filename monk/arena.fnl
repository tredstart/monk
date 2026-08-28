;; @module monk.typing
;; Symbol table with scope chains for the Monk compiler.
;; Walks AST and builds a stack of scopes where each scope maps
;; names to entity descriptors (kind, storage, type, fields, etc.)
(local fennel (require :fennel))

(local M {})

(local a-table {})

(macro arena [context]
  `{:arena [(table.unpack ,context)]})

(macro create-context [args context location]
  `(let [arena-name# (. (. ,args 1) :name)]
     (table.insert ,context {:sign arena-name# :location ,location})))

(macro dbg [msg val]
  `(print ,msg (fennel.view ,val)))

(fn return-exists [last-result variables]
  (and last-result (. variables last-result)))

(local ANY {:sign :<any> :location :<unknown>})
(fn handle-fn [function]
  (local signature {:parameters {} :return nil})
  (var last-result nil)
  (local context [ANY])
  (local variables {})
  (each [_ p (ipairs function.params)]
    (let [param (. p 1)
          vals (arena context)]
      (dbg :vals param)
      (set (. signature.parameters param.id) vals)
      (set (. variables param.id) vals)))
  (each [_ v (ipairs function.body)]
    (case v
      {:tag :form :name :in-new :args _} (create-context v.args context :inner)
      {:tag :form :name :in :args _} (create-context v.args context :outer)
      (where {: tag :expr {:tag :form :name :new}}
             (or (= tag :box/mut-def) (= tag :box-def)))
      (set (. variables v.name) (arena context))
      {:tag :atom : id} (set last-result id)
      _ (print "looking at: " (fennel.view v))))
  (let [re (return-exists last-result variables)
        arena-on-return (and re re.arena)]
    (dbg :aor arena-on-return)
    (when arena-on-return
      (set signature.return ANY.sign)
      (var inner-sign nil)
      (var outer-sign nil)
      (each [_ a (ipairs arena-on-return)]
        (if (= a.location :inner) (set inner-sign a.sign)
            (= a.location :outer) (set outer-sign a.sign)))
      (if inner-sign
          (error (string.format "Lifetime error: '%s' tries to escape context [%s]"
                                last-result inner-sign))
          outer-sign
          (set signature.return outer-sign))))
  (set (. a-table function.name) signature))

(fn handle-form [form]
  (case form.tag :fn-def (handle-fn form)))

(fn M.sign-pass [forms]
  (each [_ v (ipairs forms)]
    (handle-form v))
  a-table)

M
