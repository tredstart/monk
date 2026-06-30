(fn set-token-char [token-ref :string 
					count :i64
					char :u8
					count-ref :i64]
					(set (ref token-ref count) char)
					(set count-ref (+ count 1))
					0)

(fn read-token [file :file token-ref :string]
	(mut char-ref (getc file))
	(mut count-ref 0)
	(while (!= (i32->i64 (deref char-ref)) -1)
		(immut count (deref count-ref))
		(immut char (deref char-ref))
		(printf "%s\n: " token-ref)
		(set char-ref (getc file))
		(cond
			[(or 
				(and (>= char 65) ; A
					 (<= char 90)); Z
				(and (>= char 97)   ; a
					 (<= char 122))) ; z
					 (puts "reading a char")

				(set-token-char token-ref count char count-ref)]

			[(and (>= char 48) (<= char 57))
					 (puts "reading a number")
				(set-token-char token-ref count char count-ref)]
			[(or (= char 40) ; (
				 (= char 91)); [
				(puts "form/list opening")
				]
			[(or (= char 41); )
				 (= char 93)); ]
				(puts "form/list closing")
				]))
	token-ref)

(fn main []
  (printf "args: %d\n" argc)
  (cond
      [(>= argc 2)
		  (immut filename (idx argv 1))
		  (immut file (fopen filename "r"))
		  (cond [(= file 0) 
		     (puts "not good")
		     (exit 1)])
		  (immut token-ref (alloc8 (* 8 128)))
		  (read-token file token-ref)
		  (fclose file)]
	   ; TODO: extend parser to allow ints/floats/bools
	   [(< argc 2) (puts "it works!")])
  0)
