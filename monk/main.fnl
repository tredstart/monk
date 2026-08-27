(local fennel (require :fennel))
(local parse (require :monk.parse))
(local typing (require :monk.typing))
(local arena (require :monk.arena))

(local args [...])
(if (= (length args) 0)
    (do
      (io.stderr:write "Usage: fennel monk/main.fnl [--type|-t] [--arena|-a] <filename>
")
      (os.exit 1))
    (let [{: do-type? : do-arena? : filename} (accumulate [res {:do-type? false
                                                                :do-arena? false} _ arg (ipairs args)]
                                                (case arg
                                                  (where (or :--type :-t)) (doto res
                                                                             (tset :do-type?
                                                                                   true))
                                                  (where (or :--arena :-a)) (doto res
                                                                              (tset :do-arena?
                                                                                    true))
                                                  f (doto res
                                                      (tset :filename f))))
          forms (parse.parse-file filename)]
      (if (= (length forms) 0)
          (print :EOF)
          (do
            (each [_ f (ipairs forms)]
              (print "----- FORMS table-----")
              (print (fennel.view f)))
            (when do-type?
              (print "\n--- Symbol Table ---")
              (let [chain (typing.typing-pass forms)]
                (typing.dump-symtab chain)))
            (when do-arena?
              (print "\n--- ARENA TABLE ---")
              (let [result (arena.sign-pass forms)]
                (print (fennel.view result))))))))
