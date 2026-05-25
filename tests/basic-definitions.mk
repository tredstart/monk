(fn a-function [])

(fn multiparam [a :int b :float ... :char])

(fn single-param [a :struct])

(fn invalid-id [? (option :bool)])

(immut a "hello")

(immut sum (+ a b))


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
; (fn sum-abs [nums (list :int)]
;   (foldl nums 0 + (fn [item]   ; anonymous fn — future feature, commented below
;     (abs item))))
