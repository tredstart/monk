(local M {})

;; @function die
;; @param st table reader state
;; @param msg string
(fn die [st msg]
  (error (.. msg " (line " st.line ", col " st.col ")")))

;; @function eof?
;; @param st table
(fn eof? [st]
  (> st.i (length st.src)))

;; @function peek
;; @param st table
(fn peek [st]
  (and (not (eof? st)) (st.src:sub st.i st.i)))

;; @function peek-next
;; @param st table
;; @return string|nil the char at position i+1
;; @return boolean true when past the end
(fn peek-next [st]
  (if (<= (+ st.i 1) (length st.src))
      (values (st.src:sub (+ st.i 1) (+ st.i 1)) false)
      (values nil true)))

;; @function bump
;; @param st table
(fn bump [st]
  (if (= (peek st) "\n")
      (do
        (set st.line (+ st.line 1))
        (set st.col 1))
      (set st.col (+ st.col 1)))
  (set st.i (+ st.i 1))
  st)

;; @function skip-line
;; @param st table
(fn skip-line [st]
  (let [c (peek st)]
    (if (or (not c) (= c "\n"))
        st
        (skip-line (bump st)))))

;; @function ws?
;; @param c string|nil
(fn ws? [c]
  (and c (c:match "[%s,]")))

;; @function skip-ws
;; @param st table
(fn skip-ws [st]
  (let [c (peek st)]
    (if (ws? c) (skip-ws (bump st))
        (= c ";") (skip-ws (skip-line st))
        true st)))

;; @function delim?
;; @param c string|nil
(fn delim? [c]
  (or (not c) (string.find "()[]{}\";'," c 1 true) (ws? c)))

;; @function read-sym
;; @param st table
;; @param acc string symbol built so far
(fn read-sym [st acc]
  (let [c (peek st)]
    (if (delim? c)
        acc
        (read-sym (bump st) (.. acc c)))))

;; @function number-start?
;; @param st table
(fn number-start? [st]
  (let [c (peek st)
        (n oob) (peek-next st)]
    (or (and c (c:match "%d")) (and (= c "-") (not oob) (n:match "%d"))
        (and (= c "+") (not oob) (n:match "%d"))
        (and (= c ".") (not oob) (n:match "%d")))))

;; @function read-number
;; @param st table
;; @param line number
;; @param col number
;; @param tok string number text so far
(fn read-number [st line col tok]
  (let [c (peek st)]
    (if (and c (string.find c "[%w%+%-%.]"))
        (read-number (bump st) line col (.. tok c))
        (let [val (tonumber tok)]
          (if (not val)
              (die st (.. "bad number '" tok "'"))
              {:tag (if (string.find tok "[%.eE]") :float :int)
               : val
               : line
               : col})))))

;; @function read-escape
;; @param st table
;; @return string the escaped character
(fn read-escape [st]
  (bump st)
  (let [c (peek st)]
    (bump st)
    (case c
      :n "\n"
      :t "\t"
      "\\" "\\"
      "\"" "\""
      _ (or c ""))))

;; @function read-string
;; @param st table
;; @param acc string content so far
(fn read-string [st acc]
  (let [c (peek st)]
    (if (not c) (die st "unterminated string")
        (= c "\"") (do
                     (bump st) acc)
        (= c "\\") (read-string st (.. acc (read-escape st)))
        true (read-string (bump st) (.. acc c)))))

;; @function read-quote-or-char
;; @param st table
;; @return table|nil a char token, or nil when the ' was a quote
(fn read-quote-or-char [st]
  (let [line st.line
        col st.col]
    (bump st)
    (let [a (peek st)
          b (peek-next st)]
      ;; model: we are just past an opening '; a char literal is exactly
      ;; one non-quote character between quotes, otherwise ' quotes the
      ;; next form. a quoted form running into a ' is a malformed char.
      (assert (not (= a "'"))
              "char literal body must be a single non-quote char")
      (if (and b (= b "'"))
          (do
            (bump st) (bump st) {:tag :char :val a : line : col})
          nil))))

;; @function M.read-list-acc
;; @param st table
;; @param closer string
;; @param shape keyword
;; @param line number
;; @param col number
;; @param items list
(fn M.read-list-acc [st closer shape line col items]
  (skip-ws st)
  (let [c (peek st)]
    (if (not c) (die st (.. "unterminated list, expected '" closer "'"))
        (= c closer) (do
                       (bump st)
                       {:tag :list : shape : items : line : col})
        true (let [item (M.read-token st)]
               (table.insert items item)
               (M.read-list-acc st closer shape line col items)))))

;; @function M.read-list
;; @param st table
;; @param opener string
;; @param line number
;; @param col number
(fn M.read-list [st opener line col]
  (let [closer (case opener
                 "(" ")"
                 "[" "]"
                 "{" "}")
        shape (case opener
                "(" :paren
                "[" :bracket
                "{" :brace)]
    (bump st)
    (M.read-list-acc st closer shape line col [])))

;; @function M.read-token
;; @param st table
;; @return table token
(fn M.read-token [st]
  (skip-ws st)
  (let [line st.line
        col st.col
        c (peek st)]
    (if (not c) (die st "unexpected end of input") (= c "(")
        (M.read-list st "(" line col) (= c "[") (M.read-list st "[" line col)
        (= c "{") (M.read-list st "{" line col)
        (or (= c ")") (= c "]") (= c "}")) (die st (.. "unexpected '" c "'"))
        (= c "\"") {:tag :str :val (read-string (bump st) "") : line : col}
        (= c "'")
        (let [ch (read-quote-or-char st)]
          (if ch
              ch
              (let [item (M.read-token st)]
                (if (= (peek st) "'")
                    (die st "quote ends with a stray quote")
                    {:tag :quote : item : line : col})))) true
        (if (number-start? st)
            (read-number st line col "")
            {:tag :sym :str (read-sym st "") : line : col}))))

;; @function read-source-acc
;; @param st table
;; @param out list
(fn read-source-acc [st out]
  (skip-ws st)
  (if (eof? st)
      out
      (let [tok (M.read-token st)]
        (table.insert out tok)
        (read-source-acc st out))))

;; @function read-source
;; @param src string
;; @return list tokens
(fn read-source [src]
  (read-source-acc {: src :i 1 :line 1 :col 1} []))

;; @function read-file
;; @param path string
;; @return list tokens
(fn read-file [path]
  (let [f (io.open path :r)]
    (when (not f)
      (error (.. "could not open " path)))
    (let [src (f:read :a)]
      (f:close f)
      (read-source src))))

{: read-source : read-file}
