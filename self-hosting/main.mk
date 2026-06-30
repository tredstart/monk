
(fn emit-instruction [c :char]
	(printf "%c" (deref c)))

(fn main []
  (printf "args: %d\n" argc)
  (cond
      [(>= argc 2)
		  (immut filename (idx argv 1))
		  (immut file (fopen filename "r"))
		  (cond [(= file 0) 
		     (puts "not good")
		     (exit 1)])
		  (mut char (getc file))
		  (while (!= (i32->i64 (deref char)) -1)
			(emit-instruction char)
		  	(set char (getc file)))
		  (fclose file)]
	   ; TODO: extend parser to allow ints/floats/bools
	   [(< argc 2) (puts "it works!")])
  0)
