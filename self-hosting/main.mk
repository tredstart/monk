(fn main []
  (printf "args: %d\n" argc)
  ;; yo so this multibranching doesn't work right now
  ;; cond is more like when
  (cond 
      [(>= argc 2)
		  (immut filename (idx argv 1))
		  (immut file (fopen filename "r"))
		  (cond [(= file 0) 
		     (puts "not good")
		     (exit 1)])
		  (immut line 0) ; a null pointer
		  (immut len 0)
;		  (while (!= (getline line len file) -1)
;		    (printf "%s\n" line))
		  (fclose file)
		  ]
	   ; TODO: extend parser to allow ints/floats/bools
	   [(< argc 2) (puts "it works!")])
  0)
