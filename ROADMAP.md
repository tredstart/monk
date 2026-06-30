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
- **The bootstrap compiler doesn't need complex built-ins.** It needs calls to C functions for strings, lists, file I/O, and `system()`.
- **Monk calls C directly.** QBE handles function calls seamlessly; we don't need a heavy FFI layer. If it's too hard to do in Monk, write a C helper.
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

*Monk doesn't need complex built-ins to compile itself. It needs calls to C.*

| Week | The Monk/Racket compiler learns to emit | Because the Monk compiler needs |
|---|---|---|
| **2** | `int-lit`, `string-lit`, `atom` (variable refs), `form` (function calls). Arithmetic `+ - * /`. | Reading source, printing output, basic math |
| **3** | `fn-def` with params. `cond-expr`/`if`. Recursion. `let-def` | Recursive descent parser, control flow |
| **4** | Call C helpers for: String ops (`concat`, `ref`, `append`), List ops (`cons`, `car`, `cdr`) | Building and walking the AST |
| **5** | Call C helpers for: File I/O (`fopen`, `fgetc`), FFI (`system`) | Reading source, calling external tools |
| **6** | `immut-def`, symbol equality, tagged lists for AST nodes | Symbol table, parser tags |

**Week 6 deliverable:** A working Racket compiler that can compile any program written in the S subset. This subset can call C functions, making it I/O-capable and Turing-complete.

---

### Phase 2: Write the Compiler in Monk (Weeks 7-8)

*This is the heart of the project. A compiler, written in its own language, compiled by its own earlier self.*

`compiler.mk` will be ~400 lines of Monk organized as:

```
compiler.mk
|- call C to read source file -> string        (C-backed file I/O)
|- parse S-expressions -> tagged list AST      (recursive descent parser)
|- walk AST -> emit QBE string                 (tag dispatch codegen)
|- call C to write .ssa to disk                (C-backed file I/O)
|- call C system() to invoke qbe + gcc         (C-backed OS interface)
```

---

### Phase 3: Bootstrap (Week 9)

*The moment of truth.*

```bash
$ racket compile.rkt compiler.mk -o monkc     # Racket compiles the Monk compiler
$ ./monkc compiler.mk -o monkc2               # Monk compiler compiles itself
$ diff -b monkc monkc2                        # idempotent?
```

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

---

### Phase 5: UDP + ANSI Demo (Weeks 15-18)

*Conference is weeks away. Time to build something impressive.*

| Week | What happens |
|---|---|
| **15** | Add UDP socket wrappers to `runtime.c`. Monk calls them directly. |
| **16** | Write `udp-server.mk` and `udp-client.mk` in pure Monk. AOT compiled. |
| **17** | ANSI terminal library in Monk calling C wrappers for stdout. UI in Monk. |
| **18** | Polish. Demo. |

---

### Phase 6: Conference Buffer (Weeks 19-20)

*No new features. Polish, fix, rehearse.*

---

## Post-Conference (December - January)

*The thesis work begins. The novel contribution.*

| Month | Focus |
|---|---|
| **December** | `types.rkt` -- full type checker. `escape.rkt` -- BAMM scope/escape check. |
| **January** | Compaction (Rule 8), Pinning (Rule 10), Formal proof sketches. |

---

## Thesis Writing (February - April)

*The compiler is done. Stop touching it.*

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Bootstrap doesn't work | Conference-mode: use Racket compiler directly. Same binaries. |
| C runtime gets complex | Keep it thin. C only does what Monk can't do efficiently yet. |
| Thesis deadline | Hard feature freeze Feb 1st. |

---

## What We're NOT Building (Consciously)

- Generics, type inference, closures, lambda lifting.
- A standard library (beyond helpers needed for bootstrap).
- Optimizations of any kind.
- Windows support.

*Let's go build it.*
