# BAMM / Monk - Makefile
#
# Targets:
#   make              - build runtime tests with ASAN + UBSan and run
#   make valgrind     - build runtime tests and run under valgrind
#   make compile      - compile a .mk source to a native binary
#                       Usage: make compile FILE=hello.mk [NAME=hello]
#   make run          - compile + run a .mk source
#   make clean        - remove binaries

CC       = gcc
RKT      = racket
SRCS     = test_runtime.c runtime.c
CFLAGS   = -std=c11 -g -O0 -Wall -Wextra -Wpedantic

# Runtime test suite (ASAN)
ASAN_BIN  = test_runtime_asan
ASAN_FLAGS = -fsanitize=address,undefined \
             -fno-omit-frame-pointer \
             -DASAN_BUILD

# Runtime test suite (Valgrind)
VG_BIN    = test_runtime_vg
VG_CFLAGS = -DHAS_VALGRIND

# Monk compiler
FILE      ?= tests/hello-world.mk
NAME      ?= $(basename $(notdir $(FILE)))

.PHONY: all run compile valgrind clean

all: $(ASAN_BIN)
	@echo ""
	@echo "=== Running with ASAN + UBSan ==="
	./$(ASAN_BIN)

$(ASAN_BIN): $(SRCS)
	$(CC) $(CFLAGS) $(ASAN_FLAGS) -o $@ $^

$(VG_BIN): $(SRCS)
	$(CC) $(CFLAGS) $(VG_CFLAGS) -o $@ $^

valgrind: $(VG_BIN)
	@echo ""
	@echo "=== Running under Valgrind (memcheck) ==="
	valgrind \
	  --tool=memcheck \
	  --leak-check=full \
	  --show-leak-kinds=all \
	  --track-origins=yes \
	  --undef-value-errors=yes \
	  --error-exitcode=1 \
	  ./$(VG_BIN)

# Monk compiler pipeline

OUT       ?= bin/$(NAME)

compile: bin-dir clean-mk
	$(RKT) compile.rkt $(FILE) -o $(NAME)

run: compile
	$(OUT)

# Cleanup

bin-dir:
	mkdir -p bin

clean-mk:
	rm -f bin/$(NAME) bin/$(NAME).ssa bin/$(NAME).s bin/$(NAME).o

clean: clean-mk
	rm -f $(ASAN_BIN) $(VG_BIN)
