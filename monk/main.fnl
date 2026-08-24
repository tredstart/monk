(local fennel (require :fennel))
(local parse (require :monk.parse))
(local typing (require :monk.typing))

(local args [...])
(if (= (length args) 0)
    (do
      (io.stderr:write "Usage: fennel monk/main.fnl [--type|-t] <filename>\n")
      (os.exit 1))
    (let [do-type? (or (= (. args 1) :--type) (= (. args 1) :-t))
          filename (if do-type? (. args 2) (. args 1))
          forms (parse.parse-file filename)]
      (if (= (length forms) 0)
          (print :EOF)
          (do
            (each [_ f (ipairs forms)]
              (print (fennel.view f)))
            (when do-type?
              (print "\n--- Symbol Table ---")
              (let [chain (typing.typing-pass forms)]
                (typing.dump-symtab chain)))))))
