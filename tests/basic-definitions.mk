(fn a-function [])

(fn multiparam [a :int b :float ... :char])

(fn single-param [a :struct])

; (fn invalid-id [? (option :bool)]) <- ignore generics for the moment

(immut a "hello")

(immut sum (+ a b))


(fn add-float [a :int b :float]
  (+ (int->float a) b))

(fn distance [p1 :point p2 :point]
  (let [dx (- p2.x p1.x)
        dy (- p2.y p1.y)]
    (math.sqrt (+ (* dx dx) (* dy dy)))))

(let-mut [a .1 b .5]
  (if (= b 0.0)
    (err div-by-0 "division by zero")
    (ok  (/ a b))))

(fn is-adult [p :person]
  (>= p.age 18))

(fn maybe-greet [p :person]
  (when (and (is-adult p) p.active)
    (print "hello " p.name "!\n")))

(enum error [not-found bad-request])
(enum wht [])
(union option {
	ok :bool
	value :t
})

(struct person {
    name :string
    age :int
	is-active :bool
})

