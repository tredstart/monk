# Monk Compiler -- The Road to Self-Hosting

> **Time:** June 2026 - April 2027
> **Conference:** November 2026
> **Thesis:** April 2027
>
> *The goal: a self-hosted, AOT-compiled language with arena-based memory safety,
> that can build its own compiler and run a UDP chat server with colored terminal
> output. And then prove the safety model in a thesis.*

---

## Why This Roadmap Exists

Three milestones, each self-contained, each building on the last:

1. **November (conference):** `./monkc hello.mk` produces a binary, *and* `monkc` was compiled by a previous `monkc`. Along the way we'll demo a UDP chat server and client with ANSI terminal output -- compiled from Monk, running on bare metal, no interpreter in sight.

2. **January (feature complete):** Type checker, arena escape analysis (the thesis contribution), compaction, pinning. The full BAMM memory model running.

3. **April (thesis):** Stop coding. Write. Prove the rules, evaluate the tradeoffs, compare with Rust and Cyclone. The compiler is done -- let it speak for itself.

---

## The Philosophy

We're not building GCC. We're building a **proof of concept** for a novel memory model. That means:

- **Ship early, ship often.** Every phase produces a working binary.
- **The bootstrap compiler doesn't need structs.** It needs strings, lists, conditionals, recursion, file I/O, and `system()`. That's a *smaller* language than the full Monk.
- **Every new feature bootstraps itself.** Add it to `compiler.mk`, recompile the compiler with itself, and now the feature exists in the self-hosted world.
- **When in doubt, cut.** Generics? No. Closures? No. Optimizations? No. We have a thesis to write.

---

## Timeline

```
Jun  Jul  Aug  Sep  Oct  Nov  Dec  Jan  Feb  Mar  Apr
####  ####  ####  ####  ####  ####  ####  ####  ####  ####  ####
Phase 0-3         Phase 4-5  ^          Only thesis
Pipeline-Bootstrap-UDP+ANSI  |          writing
                              |
                        Conference
```

---

## Pre-Conference (June - November)

### Phase 0: Make It Compile (Week 1)

*The simplest possible pipeline. Hardcoded, ugly, runs.*

- Install QBE
- Write `compile.rkt` -- the skeleton that will one day be the compiler driver
- Write just enough `codegen.rkt` to emit a valid QBE program that returns 42
- Verify: `racket compile.rkt` -> `.ssa` -> `qbe` -> `.s` -> `as` -> `.o` -> `ld + runtime` -> binary -> `./a.out` prints 42

**This is the hardest week disguised as the easiest.** Every subsequent phase just adds more AST nodes to the emitter. The pipeline itself never changes.

---

### Phase 1: The Bootstrap Subset (Weeks 2-6)

*Monk doesn't need structs or enums to compile itself. It needs:*

| Week | The Racket compiler learns to emit | Because the Monk compiler needs |
|---|---|---|
| **2** | `int-lit`, `string-lit`, `atom` (variable refs), `form` (function calls). Arithmetic `+ - * /`. `print` FFI | Reading source, printing output, basic math for string processing |
| **3** | `fn-def` with params. `cond-expr`/`if`. Recursion. `let-def` | Recursive descent parser, control flow |
| **4** | String ops: `string-length`, `string-ref`, `string-append`, `string-slice`, `string=?`. List ops: `cons`, `car`, `cdr`, `nil?`, `list` | Building and walking the AST -- this is the big one |
| **5** | File I/O: `(read-file path) -> string`. FFI `system`: `(system "qbe ...")` | Reading source, calling external tools |
| **6** | `immut-def`, symbol equality, tagged lists for AST nodes | Symbol table, parser tags |

**Week 6 deliverable:** A working Racket compiler that can compile any program written in the S subset. This subset is now **Turing-complete and I/O-capable** -- you can write anything you want in it, including a compiler.

---

### Phase 2: Write the Compiler in Monk (Weeks 7-8)

*This is the heart of the project. A compiler, written in its own language, compiled by its own earlier self.*

`compiler.mk` will be ~400 lines of Monk organized as:

```
compiler.mk
|- read source file -> string               (file I/O)
|- parse S-expressions -> tagged list AST    (recursive descent parser)
|   |- parse atoms, integers, strings
|   |- parse lists -> function calls
|   |- parse fn, immut, let, cond
|   |- parse struct, enum, union, match
|- walk AST -> emit QBE string               (tag dispatch codegen)
|   |- emit arithmetic, calls
|   |- emit fn bodies with prologue/epilogue
|   |- emit struct offsets, field access
|   |- emit arena alloc/free
|- write .ssa to disk                       (file I/O)
|- call qbe + gcc via FFI system()          (OS interface)
```

The parser is a recursive descent S-expression reader, maybe 120 lines:

```racket
(fn parse-expr [src :string pos :int]
  (cond
    [(= (string-ref src pos) #\() (parse-list src (+ pos 1))]
    [(= (string-ref src pos) #\") (parse-string src (+ pos 1))]
    [(char-digit? (string-ref src pos))  (parse-number src pos)]
    [else (parse-symbol src pos)]))
```

The codegen is even simpler -- tag dispatch emitting QBE text:

```racket
(fn emit [ast :(list)]
  (match (car ast)
    [.int-lit    (emit-int (cadr ast))]
    [.fn-def     (emit-fn (cadr ast) (caddr ast) (cadddr ast))]
    [.form       (emit-call (cadr ast) (caddr ast))]
    ...))
```

---

### Phase 3: Bootstrap (Week 9)

*The moment of truth. Three commands.*

```bash
$ racket compile.rkt compiler.mk -o monkc     # Racket compiles the Monk compiler
$ ./monkc compiler.mk -o monkc2               # Monk compiler compiles itself
$ diff -b monkc monkc2                        # idempotent?
```

This week will be **debugging hell**. Every mistake in the parser, every omission in the codegen, every edge case in string handling will surface as a cryptic segfault or wrong output. That's normal. The bootstrap is the ultimate test -- it finds every bug in your compiler.

**Milestone:** `./monkc hello.mk` produces a working binary, and `monkc` was compiled by itself.

---

### Phase 4: Full Language via Self-Hosted Compiler (Weeks 10-14)

*Now we have a self-hosted compiler. Every feature we add gets bootstrapped immediately.*

| Week | Add to `compiler.mk` | Unlocked Monk feature |
|---|---|---|
| **10** | `struct-def` parsing + offset layout in QBE | `(struct point {x :float y :float})` |
| **11** | `enum-def`, `union-def` + tag dispatch | Algebraic data types |
| **12** | `match-expr` -> tag comparison chains | Pattern matching |
| **13** | `field-access` -> offset load/store | `point.x`, `person.age` |
| **14** | `mut-def`, `set` -> load/store | Mutation |

The cycle for each feature:
1. Add parsing + codegen to `compiler.mk`
2. `./monkc compiler.mk -o monkc2`
3. Write a test program using the new feature
4. `./monkc2 test.mk -o test && ./test`

---

### Phase 5: UDP + ANSI Demo (Weeks 15-18)

*Conference is weeks away. Time to build something impressive.*

| Week | What happens |
|---|---|
| **15** | Add `bamm_string_t` (ptr+len struct) and UDP socket wrappers to `runtime.c`. Declare them as FFI in the compiler. Now Monk can open sockets. |
| **16** | Write `udp-server.mk` and `udp-client.mk` in pure Monk. Test: server listens, client sends, server echoes back. All compiled AOT. |
| **17** | ANSI terminal library in Monk: `(ansi.red "text")`, `(ansi.bold "text")`, `(ansi.gotoxy 5 10)`, `(ansi.clear)`. Wrap the UDP client in a terminal chat UI with colored messages, a scrollable message area, and an input line. |
| **18** | Polish the demo. Fix crash-on-disconnect. Handle partial packets. Clean exit on Ctrl-C. Write the conference demo script. |

---

### Phase 6: Conference Buffer (Weeks 19-20)

*No new features. Polish, fix, rehearse.*

- Edge case fixes in the self-hosted compiler
- Error messages that don't look like alien transmissions
- A clean `--help` output
- Demo scripts that won't fail on stage
- Backup plan: if the demo laptop doesn't have QBE, pre-compile everything

---

## Post-Conference (December - January)

*The thesis work begins. The novel contribution.*

| Month | Focus |
|---|---|
| **December** | `types.rkt` -- full type checker. `escape.rkt` -- scope tree construction, arena assignment, escape check. This is Rule 5 -- the novel BAMM rule that makes compaction safe. Every program that passes the checker is guaranteed arena-safe. |
| **January** | Compaction (Rule 8) -- iterate over all handles in a scope, move objects, update references in place. Pinning (Rule 10) -- mark arenas as unpinnable for FFI safety. Write the formal proof sketches that will go in the thesis. |

---

## Thesis Writing (February - April)

*The compiler is done. Stop touching it.*

- **Chapter 1:** Problem statement -- memory safety without GC or borrow checker
- **Chapter 2:** Background -- C/C++ unsafety, GC tradeoffs, Rust complexity, region systems (Tofte-Taplin, Cyclone)
- **Chapter 3:** BAMM formal definition -- 10 rules, escape inference system, compaction safety theorem
- **Chapter 4:** Implementation -- compiler pipeline, escape analysis algorithm, arena runtime
- **Chapter 5:** Evaluation -- compile-time vs. Rust borrow checker, expressiveness tradeoffs, benchmark comparisons
- **Chapter 6:** Future work -- message passing, region inference, compaction policies
- **Appendix:** Full compiler source listing, bootstrap proof

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Bootstrap doesn't work by week 9 | Conference-mode: use Racket compiler directly. Same binaries, different origin story. |
| UDP is too complex for FFI | High-level C wrappers: `bamm_udp_server(port)`, `bamm_udp_send(handle, data)`. Monk never touches `sockaddr_in`. |
| String handling is buggy | The C runtime handles string_t as a robust ptr+len struct. Monk strings are just bytes + length. No null termination surprises. |
| Compiler is too slow | It's a PoC. If it takes 5 seconds to compile itself, that's fine. If it takes 5 minutes, we have a problem. |
| Thesis deadline looming | Hard feature freeze February 1st. Bug fixes only. The thesis is the point, not the compiler. |

---

## What We're NOT Building (Consciously)

- Generics, type inference, closures, lambda lifting
- A standard library (beyond what's needed for bootstrap + demo)
- Error recovery in the parser (fail fast, fail hard)
- Optimizations of any kind
- Incremental compilation
- A debugger, profiler, or language server
- Thread safety (everything is single-threaded)
- A package manager or module system
- Windows support

These can all come later -- after the thesis, after the defense, after the conference. Right now we're building one thing: **a self-hosted compiler that proves BAMM works, and a demo that proves it's useful.**

---

*Let's go build it.*
