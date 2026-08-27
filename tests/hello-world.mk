(fn make-value [ctx :i32] :i32
  (in-new 'arena-b)
  (box y :i32 (new (+ ctx 1)))   ;; y lives in arena-b
  y)                               ;; arena-b dies on return — y is already dangling

(fn main [] :u8
  (in-new 'arena-a)
  (box x :i32 (new 42))

  (box y :i32 (make-value x))          ;; ERROR: y's arena (arena-b) is dead at this point
  (puts y))


