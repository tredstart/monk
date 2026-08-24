;; @class atom
;; @field id string
(fn atom [id] {:tag :atom : id})

;; @class int-lit
;; @field value number
(fn int-lit [value] {:tag :int-lit : value})

;; @class float-lit
;; @field value number
(fn float-lit [value] {:tag :float-lit : value})

;; @class string-lit
;; @field content string
(fn string-lit [content] {:tag :string-lit : content})

;; @class char-lit
;; @field ch string
(fn char-lit [ch] {:tag :char-lit : ch})

;; @class type-ref
;; @field id string
(fn type-ref [id] {:tag :type-ref : id})

;; @class field-access
;; @field target node
;; @field field string
(fn field-access [target field] {:tag :field-access : target : field})

;; @class struct-def
;; @field name string
;; @field fields list
(fn struct-def [name fields] {:tag :struct-def : name : fields})

;; @class union-def
;; @field name string
;; @field variants list
(fn union-def [name variants] {:tag :union-def : name : variants})

;; @class enum-def
;; @field name string
;; @field variants list
(fn enum-def [name variants] {:tag :enum-def : name : variants})

;; @class enum-variant
;; @field name string
(fn enum-variant [name] {:tag :enum-variant : name})

;; @class union-variant
;; @field name string
;; @field id string
(fn union-variant [name id] {:tag :union-variant : name : id})

;; @class box-def
;; @field name string
;; @field expr node
(fn box-def [name t expr] {:tag :box-def :type t : name : expr})

;; @class box/mut-def
;; @field name string
;; @field expr node
(fn box/mut-def [name t expr] {:tag :box/mut-def :type t : name : expr})

;; @class val-def
;; @field name string
;; @field expr node
(fn val-def [name t expr] {:tag :val-def :type t : name : expr})

;; @class bool-def
;; @field id boolean
(fn bool-def [id] {:tag :bool-def : id})

;; @class fn-def
;; @field name string
;; @field params list
;; @field body list
(fn fn-def [name params return-type body]
  {:tag :fn-def : name : params : return-type : body})

;; @class match-arm
;; @field pattern node
;; @field expr list
(fn match-arm [pattern expr] {:tag :match-arm : pattern : expr})

;; @class match-expr
;; @field target node
;; @field arms list
(fn match-expr [target arms] {:tag :match-expr : target : arms})

;; @class cond-arm
;; @field condition node
;; @field expr list
(fn cond-arm [condition expr] {:tag :cond-arm : condition : expr})

;; @class cond-expr
;; @field arms list
(fn cond-expr [arms] {:tag :cond-expr : arms})

;; @class let-def
;; @field bindings list
;; @field body list
(fn let-def [bindings body] {:tag :let-def : bindings : body})

;; @class let-mut-def
;; @field bindings list
;; @field body list
(fn let-mut-def [bindings body] {:tag :let-mut-def : bindings : body})

;; @class form
;; @field name string
;; @field args list
(fn form [name args] {:tag :form : name : args})
(fn package [name] {:tag :package : name})

{: atom
 : int-lit
 : float-lit
 : string-lit
 : char-lit
 : type-ref
 : field-access
 : struct-def
 : union-def
 : enum-def
 : enum-variant
 : union-variant
 : box-def
 : box/mut-def
 : val-def
 : bool-def
 : fn-def
 : match-arm
 : match-expr
 : cond-arm
 : cond-expr
 : let-def
 : let-mut-def
 : form
 : package}
