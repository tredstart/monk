(fn make-value [ctx :i32 adder :i32] :i32
  (in-new 'arena-b)
  (box y :i32 (new (+ ctx adder)))   ;; y lives in arena-b
  (in-new 'arena-down)
  (box x :i32 (new (+ ctx adder)))   ;; y lives in arena-b
  x)                               ;; arena-b dies on return — y is already dangling

(fn main [] :u8
  (in-new 'arena-a)
  (box x :i32 (new 42))

  (box y :i32 (make-value x 3))          ;; ERROR: y's arena (arena-b) is dead at this point
  (puts y))


