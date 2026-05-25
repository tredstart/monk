; ============================================================
; comprehensive language example
; covers: require, immut, mut, struct, union, enum, type (alias + adt),
;         fn, let, let-mut, set, if, when, cond, for, match,
;         ++, --, +=, -=, option type, result type, foldl, append
; ============================================================

; --- module imports ---
(immut core   (require 'core))
(immut math   (require 'math))

; --- bring specific bindings into scope ---
(immut abs    core.abs)
(immut print  core.print)
(immut input  core.input)

; ============================================================
; type definitions
; ============================================================

; plain struct
(struct point {
  x :float
  y :float
})

; struct with more fields
(struct person {
  name   :string
  age    :int
  active :bool
})

; tagged union — each variant carries a payload
(union shape {
  circle  :float      ; radius
  rect    :point      ; width+height packed as a point
  nothing :bool       ; sentinel / unit-like variant
})

; enum — no payloads, pure variants
(enum direction [north south east west])

(enum color [red green blue])

; simple type alias
(type coord point)

; adt: option — built-in but shown here for clarity
; (type (option t)
;   none
;   t)

; (type err (struct {
;   code :int ; or error num?
;   msg :string
; }))

; (type (ok t) t)

; adt: result — two-variant type carrying ok value or error string
; (type (result t)
;   err
;  (ok  t))

; ============================================================
; helper functions
; ============================================================

; basic arithmetic helper — return type inferred as :float
(fn add-float [a :int b :float]
  (+ (int->float a) b))

; distance between two points
(fn distance [p1 :point p2 :point]
  (let [dx (- p2.x p1.x)
        dy (- p2.y p1.y)]
    (math.sqrt (+ (* dx dx) (* dy dy)))))

; describe a shape — demonstrates match + union destructuring
(fn describe-shape [s :shape]
  (match s
    [(.circle  r)  (print "circle with radius " r)]
    [(.rect    wh) (print "rect " wh.x " x " wh.y)]
    [_  (print "no shape")]))

; classify direction — match over enum
(fn direction-label [d :direction]
  (match d
    [.north "up"]
    [.south "down"]
    [.east  "right"]
    [.west  "left"]))

; safe division — returns a result adt
(fn safe-div [a :float b :float]
  (if (= b 0.0)
    (err div-by-0 "division by zero")
    (ok  (/ a b))))

; check if a person is an adult — demonstrates if
(fn is-adult [p :person]
  (>= p.age 18))

; greet only active adults — demonstrates when (single-branch if)
(fn maybe-greet [p :person]
  (when (and (is-adult p) p.active)
    (print "hello " p.name "!\n")))

; sum absolute values in a list — demonstrates foldl
; foldl signature: (foldl collection init reducer mapper?)
; (fn sum-abs [nums :(list :int)]
;   (foldl nums 0 + (fn [item]   ; anonymous fn — future feature, commented below
;     (abs item))))

; NOTE: anonymous fn / closures are a future feature.
; the foldl call above is aspirational syntax — parser should
; store it as an ast node but skip codegen for now.
; for current parser testing, use the non-mapper overload:
; (foldl nums 0 +)

; ============================================================
; main
; ============================================================

(fn main []

  ; --- immut / let bindings ---
  (let [origin    (point 0.0 0.0)
        target    (coord 3.0 4.0)   ; coord is alias for point
        dist      (distance origin target)
        greeting  "hello world"]

    (print greeting "\n")
    (print "distance: " dist "\n"))   ; should print 5.0

  ; --- mut + set + ++ / -- ---
  (mut counter 0)
  (++ counter)                        ; counter = 1
  (++ counter)                        ; counter = 2
  (-- counter)                        ; counter = 1
  (set counter (+ counter 10))        ; counter = 11
  (+= counter 4)                      ; counter = 15
  (-= counter 5)                      ; counter = 10
  (print "counter: " counter "\n")

  ; --- struct construction + field access ---
  (mut alice (person .name "alice" .age 30 .is-active true))
  (set alice.age (+ alice.age 1))     ; birthday
  (print "alice age: " alice.age "\n")

  (let [bob (person "bob" 16 false)]
    (maybe-greet alice)               ; prints greeting
    (maybe-greet bob))                ; silent — not adult

  ; --- union + match ---
  (let [c  (shape.circle 5.0)
        r  (shape.rect (point 10.0 3.0))
        n  (shape.nothing false)]
    (describe-shape c)
    (describe-shape r)
    (describe-shape n))

  ; --- enum + match ---
  (let [dir direction.north]
    (print (direction-label dir) "\n"))

  ; --- cond ---
  (let [score 72]
    (cond
      [(>= score 90) (print "grade: A\n")]
      [(>= score 75) (print "grade: B\n")]
      [(>= score 60) (print "grade: C\n")]
      [_             (print "grade: F\n")]))   ; _ is wildcard / default

  ; --- if as expression ---
  (let [x     -7
        abs-x (if (< x 0) (* x -1) x)]
    (print "abs(-7): " abs-x "\n"))

  ; --- for loop [name inclusive exclusive step?] ---
  (mut total 0)
  (for [i 0 10]                        ; 0..9
    (+= total i))
  (print "sum 0-9: " total "\n")       ; 45

  (for [i 0 20 2]                      ; 0,2,4,...,18 (step = 2)
    (when (> i 10)
      (print "stepped: " i "\n")))

  ; --- option type + match ---
  (mut maybe-val (option :int))        ; starts as none
  (set maybe-val 42)                ; now holds 42

  (match maybe-val
    [none   (print "no value\n")]
    [v      (print "got: " v "\n")])   ; v binds the inner int

  ; --- result type + match ---
  (let [good (safe-div 10.0 2.0)
        bad  (safe-div  5.0 0.0)]
    (match good
      [(.err msg) (print "error: " msg "\n")]
      [(.ok  val) (print "result: " val "\n")])   ; prints 5.0
    (match bad
      [(.err msg) (print "error: " msg "\n")]     ; prints "division by zero"
      [(.ok  val) (print "result: " val "\n")]))

  ; --- list + append + foldl ---
  (mut numbers (list :int))
  (append numbers 3)
  (append numbers -7)
  (append numbers 2)
  (append numbers -1)
  (append numbers 5)

  ; future works
  ; (let [total-abs (foldl numbers 0 +)]          ; basic foldl, no mapper
  ;   (print "foldl sum: " total-abs "\n"))

  ; --- let-mut: mutable binding scoped to a block ---
  (let-mut [running (point 0.0 0.0)]
    (set running.x (add-float 3 1.5))
    (set running.y (add-float 2 2.5))
    (print "running point: " running.x " " running.y "\n"))

  ; --- color enum, just to exercise all variants ---
  (for [i 0 3]
    (let [c (match i
               [0 color.red]
               [1 color.green]
               [2 color.blue]
               [_ color.red])]          ; exhaustive — wildcard needed for :int match
      (match c
        [.red   (print "red\n")]
        [.green (print "green\n")]
        [.blue  (print "blue\n")])))

  ; ============================================================
  ; future / aspirational constructs — parser should parse these
  ; into ast nodes but codegen can skip them for now
  ; ============================================================

  ; anonymous functions / closures
  ; (mut transform (fn [x :int] (* x x)))
  ; (print (transform 5) "\n")

  ; generic list with non-primitive type param
  ; (mut shapes (list :shape))
  ; (append shapes (shape.circle 1.0))

  ; pipe / threading operator
  ; (|> -9 abs print)

  ; quasiquote / macro invocation
  ; `(some-macro ,(+ 1 2))

  ; ranges / iterators
  ; (for [i (range 0 10)] (print i "\n"))

  0   ; main returns 0 (exit code inferred as :int)
)
