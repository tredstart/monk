(struct point {
  x :f32
  y :f32})

(enum sides [
  N
  W
  E
  S
])

(fn main [argc :i32 argv :string] :i32
  (box/mut name :f32 .43)
  (printf "hello, world\n")
  0)
