#include "runtime.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* -----------------------------------------------------------------------
 * Minimal test harness
 * --------------------------------------------------------------------- */
static int g_pass = 0;
static int g_fail = 0;
static const char *g_suite = "";

#define SUITE(name)                                                            \
  do {                                                                         \
    g_suite = (name);                                                          \
    printf("Running suite: %s...\n", g_suite);                                 \
  } while (0)

#define CHECK(cond)                                                            \
  do {                                                                         \
    if (cond) {                                                                \
      g_pass++;                                                                \
    } else {                                                                   \
      printf("  [FAIL] %s  (line %d) in suite: %s\n", #cond, __LINE__,         \
             g_suite);                                                         \
      g_fail++;                                                                \
    }                                                                          \
  } while (0)

#define CHECK_MSG(cond, msg)                                                   \
  do {                                                                         \
    if (cond) {                                                                \
      g_pass++;                                                                \
    } else {                                                                   \
      printf("  [FAIL] %s  (line %d) in suite: %s\n", (msg), __LINE__,         \
             g_suite);                                                         \
      g_fail++;                                                                \
    }                                                                          \
  } while (0)

static void summary(void) {
  printf("\n========================================\n");
  if (g_fail == 0) {
    printf("  SUCCESS: All %d checks passed.\n", g_pass);
  } else {
    printf("  FAILURE: %d assertions passed, %d failed\n", g_pass, g_fail);
  }
  printf("========================================\n");
  if (g_fail)
    exit(1);
}

/* -----------------------------------------------------------------------
 * Helpers
 * --------------------------------------------------------------------- */
#define PAGE 4096
#define SMALL (PAGE * 4)
#define LARGE (PAGE * 64)

/* Write a canary pattern into an allocation and verify it later */
static void write_canary(void *ptr, size_t size) {
  unsigned char *p = (unsigned char *)ptr;
  for (size_t i = 0; i < size; i++)
    p[i] = (unsigned char)(i ^ 0xA5);
}
static int check_canary(void *ptr, size_t size) {
  unsigned char *p = (unsigned char *)ptr;
  for (size_t i = 0; i < size; i++)
    if (p[i] != (unsigned char)(i ^ 0xA5))
      return 0;
  return 1;
}

/* -----------------------------------------------------------------------
 * 1. ARENA LIFECYCLE
 * --------------------------------------------------------------------- */
static void test_arena_lifecycle(void) {
  SUITE("arena lifecycle");

  handle_t a = arena_create(SMALL, PAGE);
  CHECK(a != HANDLE_INVALID);

  void *ap = resolve_handle(a);
  CHECK(ap != NULL);

  arena_free(); /* pops the arena */

  /* after free, the arena handle itself must be invalidated */
  CHECK(resolve_handle(a) == NULL);
}

static void test_arena_nested_stack(void) {
  SUITE("arena nested / LIFO stack discipline");

  handle_t a1 = arena_create(SMALL, PAGE);
  handle_t a2 = arena_create(SMALL, PAGE);
  handle_t a3 = arena_create(SMALL, PAGE);

  CHECK(a1 != HANDLE_INVALID);
  CHECK(a2 != HANDLE_INVALID);
  CHECK(a3 != HANDLE_INVALID);
  CHECK(a1 != a2 && a2 != a3);

  /* all three arenas must be resolvable while alive */
  CHECK(resolve_handle(a1) != NULL);
  CHECK(resolve_handle(a2) != NULL);
  CHECK(resolve_handle(a3) != NULL);

  arena_free(); /* pops a3 */
  CHECK(resolve_handle(a3) == NULL);
  CHECK(resolve_handle(a2) != NULL); /* a2 still alive */
  CHECK(resolve_handle(a1) != NULL); /* a1 still alive */

  arena_free(); /* pops a2 */
  CHECK(resolve_handle(a2) == NULL);
  CHECK(resolve_handle(a1) != NULL);

  arena_free(); /* pops a1 */
  CHECK(resolve_handle(a1) == NULL);
}

static void test_multiple_arena_cycles(void) {
  SUITE("arena create/free repeated cycles");
  for (int i = 0; i < 32; i++) {
    handle_t a = arena_create(SMALL, PAGE);
    CHECK_MSG(a != HANDLE_INVALID, "arena_create in cycle");
    handle_t h = arena_alloc(64);
    CHECK_MSG(h != HANDLE_INVALID, "arena_alloc in cycle");
    arena_free();
    CHECK_MSG(resolve_handle(h) == NULL,
              "handle dead after arena_free in cycle");
  }
}

/* -----------------------------------------------------------------------
 * 2. ARENA ALLOC
 * --------------------------------------------------------------------- */
static void test_alloc_basic(void) {
  SUITE("arena_alloc basic");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  handle_t h = arena_alloc(128);
  CHECK(h != HANDLE_INVALID);

  void *p = resolve_handle(h);
  CHECK(p != NULL);

  /* write and read back */
  memset(p, 0xBE, 128);
  unsigned char *cp = (unsigned char *)p;
  int ok = 1;
  for (int i = 0; i < 128; i++)
    if (cp[i] != 0xBE) {
      ok = 0;
      break;
    }
  CHECK_MSG(ok, "allocation is writable and readable");

  arena_free();
}

static void test_alloc_alignment(void) {
  SUITE("arena_alloc validation (unaligned specification)");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  /* allocate objects of varied sizes and verify pointer validity */
  size_t sizes[] = {1, 3, 7, 8, 9, 15, 16, 17, 31, 32, 64, 100, 127, 128};
  for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
    handle_t h = arena_alloc(sizes[i]);
    void *p = resolve_handle(h);
    CHECK_MSG(p != NULL, "valid layout allocation");
  }

  arena_free();
}

static void test_alloc_many(void) {
  SUITE("arena_alloc many objects");

  handle_t a = arena_create(LARGE, PAGE);
  (void)a;

  const int N = 512;
  handle_t handles[512];
  for (int i = 0; i < N; i++) {
    handles[i] = arena_alloc(64);
    CHECK_MSG(handles[i] != HANDLE_INVALID, "alloc in bulk loop");
    void *p = resolve_handle(handles[i]);
    write_canary(p, 64);
  }

  /* verify all canaries intact  no overlapping allocations */
  int all_ok = 1;
  for (int i = 0; i < N; i++) {
    void *p = resolve_handle(handles[i]);
    if (!check_canary(p, 64)) {
      all_ok = 0;
      break;
    }
  }
  CHECK_MSG(all_ok, "no allocation overlap  canaries intact");

  arena_free();
}

static void test_alloc_zero_size(void) {
  SUITE("arena_alloc edge: zero size");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  /* zero-size alloc: implementation-defined, but must not crash */
  handle_t h = arena_alloc(0);
  (void)h;
  CHECK_MSG(1, "zero-size alloc does not crash");

  arena_free();
}

static void test_alloc_exhaustion(void) {
  SUITE("arena_alloc exhaustion");

  /* arena too small to satisfy a giant request */
  handle_t a = arena_create(PAGE, PAGE);
  (void)a;

  /* try to allocate more than the reserved space */
  handle_t h = arena_alloc(LARGE);
  CHECK_MSG(h == HANDLE_INVALID, "oversized alloc returns HANDLE_INVALID");

  arena_free();
}

/* -----------------------------------------------------------------------
 * 3. ARENA RESET
 * --------------------------------------------------------------------- */
static void test_arena_reset(void) {
  SUITE("arena_reset");

  handle_t a = arena_create(SMALL, PAGE);

  handle_t h1 = arena_alloc(64);
  handle_t h2 = arena_alloc(64);
  CHECK(h1 != HANDLE_INVALID);
  CHECK(h2 != HANDLE_INVALID);

  arena_reset(); /* keeps arena, invalidates all allocations */

  CHECK_MSG(resolve_handle(h1) == NULL, "h1 dead after reset");
  CHECK_MSG(resolve_handle(h2) == NULL, "h2 dead after reset");

  /* arena itself still alive */
  CHECK_MSG(resolve_handle(a) != NULL, "arena handle still valid after reset");

  /* can allocate again */
  handle_t h3 = arena_alloc(64);
  CHECK_MSG(h3 != HANDLE_INVALID, "can alloc after reset");
  CHECK_MSG(resolve_handle(h3) != NULL, "new alloc resolves after reset");

  arena_free();
}

static void test_arena_reset_reuse(void) {
  SUITE("arena_reset repeated reuse");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  for (int round = 0; round < 16; round++) {
    handle_t h = arena_alloc(128);
    void *p = resolve_handle(h);
    CHECK_MSG(p != NULL, "alloc in reuse round");
    write_canary(p, 128);
    CHECK_MSG(check_canary(p, 128), "canary ok before reset");
    arena_reset();
    CHECK_MSG(resolve_handle(h) == NULL, "handle dead after reset in reuse");
  }

  arena_free();
}

/* -----------------------------------------------------------------------
 * 4. HANDLE INVALIDATION (use-after-free prevention)
 * --------------------------------------------------------------------- */
static void test_handle_dead_after_arena_free(void) {
  SUITE("handle invalidation after arena_free");

  handle_t a = arena_create(SMALL, PAGE);
  handle_t h = arena_alloc(256);
  CHECK(resolve_handle(h) != NULL);

  arena_free();

  /* DEAD after free must return NULL, never the stale address */
  CHECK_MSG(resolve_handle(h) == NULL, "handle resolves NULL after arena_free");
  CHECK_MSG(resolve_handle(a) == NULL,
            "arena handle resolves NULL after arena_free");
}

static void test_handle_dead_after_nested_free(void) {
  SUITE("handle invalidation in nested arenas");

  handle_t a1 = arena_create(SMALL, PAGE);
  handle_t h1 = arena_alloc(64);

  handle_t a2 = arena_create(SMALL, PAGE);
  handle_t h2 = arena_alloc(64);

  /* free inner arena */
  arena_free();
  CHECK_MSG(resolve_handle(h2) == NULL, "inner alloc dead");
  CHECK_MSG(resolve_handle(a2) == NULL, "inner arena dead");

  /* outer still alive */
  CHECK_MSG(resolve_handle(h1) != NULL, "outer alloc still alive");
  CHECK_MSG(resolve_handle(a1) != NULL, "outer arena still alive");

  arena_free();
  CHECK_MSG(resolve_handle(h1) == NULL, "outer alloc dead after outer free");
}

static void test_invalid_handle_constant(void) {
  SUITE("HANDLE_INVALID sentinel");

  /* HANDLE_INVALID must never resolve to a valid pointer */
  CHECK(resolve_handle(HANDLE_INVALID) == NULL);
}

static void test_resolve_out_of_range(void) {
  SUITE("resolve_handle out-of-range index");

  /* Handles beyond MAX_HANDLES must not crash or return garbage */
  handle_t bad = (handle_t)(MAX_HANDLES + 1000);
  void *p = resolve_handle(bad);
  CHECK_MSG(p == NULL, "out-of-range handle resolves NULL");
}

/* -----------------------------------------------------------------------
 * 5. ARENA_COPY (cross-arena deep copy - Arena Locality)
 * --------------------------------------------------------------------- */
static void test_arena_copy_basic(void) {
  SUITE("arena_copy basic");

  handle_t a1 = arena_create(SMALL, PAGE);
  (void)a1;
  handle_t h_src = arena_alloc(128);
  void *src = resolve_handle(h_src);
  write_canary(src, 128);

  handle_t a2 = arena_create(SMALL, PAGE);
  handle_t h_dest = arena_copy(a2, h_src);

  CHECK_MSG(h_dest != HANDLE_INVALID,
            "arena_copy returns a valid destination handle");
  CHECK_MSG(resolve_handle(h_dest) != NULL,
            "copied handle resolves successfully");
  CHECK_MSG(check_canary(resolve_handle(h_dest), 128),
            "copied target data matches source");

  /* source still intact */
  CHECK_MSG(check_canary(resolve_handle(h_src), 128),
            "source canary intact after copy");

  arena_free(); /* free a2 */
  arena_free(); /* free a1 */
}

static void test_arena_copy_noop_same_arena(void) {
  SUITE("arena_copy no-op when src lives in dest arena");

  handle_t a = arena_create(SMALL, PAGE);
  handle_t h = arena_alloc(64);
  void *before = resolve_handle(h);

  /* copy into the same arena must be a no-op per spec and return original
   * handle */
  handle_t h_res = arena_copy(a, h);
  CHECK_MSG(h_res == h, "same-arena copy returns original handle");

  /* handle still resolves to same address */
  CHECK_MSG(resolve_handle(h) == before, "same-arena copy is no-op");

  arena_free();
}

static void test_arena_copy_independence(void) {
  SUITE("arena_copy  copied data is independent");

  handle_t a1 = arena_create(SMALL, PAGE);
  (void)a1;
  handle_t h_src = arena_alloc(64);
  unsigned char *src = (unsigned char *)resolve_handle(h_src);
  for (int i = 0; i < 64; i++)
    src[i] = (unsigned char)i;

  handle_t a2 = arena_create(SMALL, PAGE);

  handle_t h_dest = arena_copy(a2, h_src);
  CHECK_MSG(h_dest != HANDLE_INVALID,
            "arena_copy returns valid destination handle");

  arena_free(); /* free a1, src pointer now dangling at OS level */

  /* a2 is current arena; we should be able to alloc without crash,
   * proving a2's backing store is independent of a1 */
  handle_t h_new = arena_alloc(64);
  CHECK_MSG(h_new != HANDLE_INVALID, "a2 still functional after a1 freed");

  arena_free(); /* free a2 */
}

/* -----------------------------------------------------------------------
 * 6. SUBARENA LIFECYCLE
 * --------------------------------------------------------------------- */
static void test_subarena_basic(void) {
  SUITE("subarena create / dealloc");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  handle_t sub = subarena_create();
  CHECK(sub != HANDLE_INVALID);
  CHECK(resolve_handle(sub) != NULL);

  handle_t h = arena_alloc(64); /* alloc inside subarena context */
  CHECK(h != HANDLE_INVALID);

  subarena_dealloc(); /* rewinds, invalidates h */
  CHECK_MSG(resolve_handle(h) == NULL, "subarena alloc dead after dealloc");
  CHECK_MSG(resolve_handle(sub) == NULL, "subarena header dead after dealloc");

  arena_free();
}

static void test_subarena_reset(void) {
  SUITE("subarena_reset");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;
  handle_t sub = subarena_create();

  handle_t h1 = arena_alloc(64);
  handle_t h2 = arena_alloc(64);

  subarena_reset(); /* invalidate contents, keep header */

  CHECK_MSG(resolve_handle(h1) == NULL, "h1 dead after subarena_reset");
  CHECK_MSG(resolve_handle(h2) == NULL, "h2 dead after subarena_reset");
  CHECK_MSG(resolve_handle(sub) != NULL, "subarena header alive after reset");

  /* can allocate again */
  handle_t h3 = arena_alloc(64);
  CHECK_MSG(h3 != HANDLE_INVALID, "alloc works after subarena_reset");

  subarena_dealloc();
  arena_free();
}

/* -----------------------------------------------------------------------
 * 7. SUBARENA ESCAPE
 * --------------------------------------------------------------------- */
static void test_subarena_escape_basic(void) {
  SUITE("subarena_escape basic");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;
  subarena_create();

  handle_t h = arena_alloc(64);
  void *p_before = resolve_handle(h);
  memset(p_before, 0xCA, 64);

  subarena_escape(h);

  void *p_after = resolve_handle(h);
  CHECK_MSG(p_after != NULL,
            "escaped handle still valid after escape");

  unsigned char *cp = (unsigned char *)p_after;
  int ok = 1;
  for (int i = 0; i < 64; i++)
    if (cp[i] != 0xCA) {
      ok = 0;
      break;
    }
  CHECK_MSG(ok, "escaped content intact");

  arena_free();
}

static void test_subarena_escape_does_not_corrupt_parent(void) {
  SUITE("subarena_escape does not corrupt parent arena allocations");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  /* allocate in parent first */
  handle_t parent_h = arena_alloc(128);
  write_canary(resolve_handle(parent_h), 128);

  subarena_create();
  handle_t sub_h = arena_alloc(64);
  memset(resolve_handle(sub_h), 0xFF, 64);

  subarena_escape(sub_h);

  /* parent allocation must still be intact */
  CHECK_MSG(check_canary(resolve_handle(parent_h), 128),
            "parent canary intact after subarena escape");

  arena_free();
}

/* -----------------------------------------------------------------------
 * 8. HANDLE TABLE INTEGRITY
 * --------------------------------------------------------------------- */
static void test_handle_metadata(void) {
  SUITE("handle metadata accessors");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;

  handle_t h = arena_alloc(64);
  CHECK_MSG(h != HANDLE_INVALID, "alloc for metadata test");

  uint64_t id = handle_get_id(h);
  CHECK_MSG(id > 0, "handle id is positive");

  handle_t arena_of = handle_get_arena(h);
  CHECK_MSG(arena_of == a, "handle reports correct owning arena");

  size_t sz = handle_get_size(h);
  CHECK_MSG(sz == 64, "handle reports correct allocation size");

  arena_free();
}

static void test_handle_uniqueness(void) {
  SUITE("handle uniqueness");

  handle_t a = arena_create(LARGE, PAGE);
  (void)a;

  const int N = 256;
  handle_t hs[256];
  for (int i = 0; i < N; i++) {
    hs[i] = arena_alloc(8);
    CHECK_MSG(hs[i] != HANDLE_INVALID, "alloc for uniqueness test");
  }

  /* all handles must be distinct */
  int unique = 1;
  for (int i = 0; i < N && unique; i++)
    for (int j = i + 1; j < N && unique; j++)
      if (hs[i] == hs[j])
        unique = 0;

  CHECK_MSG(unique, "all handles are distinct");

  /* all resolved pointers must be distinct (no aliasing) */
  int no_alias = 1;
  for (int i = 0; i < N && no_alias; i++)
    for (int j = i + 1; j < N && no_alias; j++)
      if (resolve_handle(hs[i]) == resolve_handle(hs[j]))
        no_alias = 0;

  CHECK_MSG(no_alias, "all allocations have distinct addresses");

  arena_free();
}

static void test_handle_table_capacity(void) {
  SUITE("handle table near-capacity stress");

  const int ARENAS = 10;
  const int ALLOCS = 100; /* 1000 handles total */

  handle_t a_handles[10];
  handle_t obj_handles[10][100];

  for (int i = 0; i < ARENAS; i++) {
    a_handles[i] = arena_create(SMALL, PAGE);
    for (int j = 0; j < ALLOCS; j++) {
      obj_handles[i][j] = arena_alloc(8);
    }
  }
  (void)a_handles;

  /* verify all still resolve */
  int ok = 1;
  for (int i = 0; i < ARENAS && ok; i++)
    for (int j = 0; j < ALLOCS && ok; j++)
      if (resolve_handle(obj_handles[i][j]) == NULL)
        ok = 0;

  CHECK_MSG(ok, "all handles resolve under stress");

  /* free in LIFO order */
  for (int i = ARENAS - 1; i >= 0; i--) {
    arena_free();
    for (int j = 0; j < ALLOCS; j++) {
      CHECK_MSG(resolve_handle(obj_handles[i][j]) == NULL,
                "handle dead after bulk free");
    }
  }
}

/* -----------------------------------------------------------------------
 * 9. DEAD-PTR CANARY
 * --------------------------------------------------------------------- */
static void test_handle_dead(void) {
  SUITE("dead handle detection");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;
  handle_t h = arena_alloc(16);
  CHECK_MSG(handle_is_alive(h), "handle alive after alloc");

  arena_free();

  CHECK_MSG(!handle_is_alive(h), "handle dead after arena_free");
  CHECK_MSG(resolve_handle(h) == NULL,
            "resolve returns NULL for dead handle");
}

/* -----------------------------------------------------------------------
 * 10. STRESS / TORTURE
 * --------------------------------------------------------------------- */
static void test_stress_nested_alloc_free(void) {
  SUITE("stress: deep nesting alloc/free");

  const int DEPTH = 16;
  handle_t arenas[16];
  handle_t allocs[16];

  for (int i = 0; i < DEPTH; i++) {
    arenas[i] = arena_create(SMALL, PAGE);
    allocs[i] = arena_alloc((size_t)(64 * (i + 1)));
    void *p = resolve_handle(allocs[i]);
    CHECK_MSG(p != NULL, "alloc in deep nest");
    memset(p, (int)(i & 0xFF), (size_t)(64 * (i + 1)));
  }

  for (int i = DEPTH - 1; i >= 0; i--) {
    arena_free();
    CHECK_MSG(resolve_handle(allocs[i]) == NULL,
              "handle dead after LIFO free in deep nest");
    /* shallower arenas still alive */
    for (int j = 0; j < i; j++)
      CHECK_MSG(resolve_handle(arenas[j]) != NULL,
                "shallower arena still alive");
  }
}

static void test_stress_subarena_cycles(void) {
  SUITE("stress: subarena create/reset/dealloc cycles");

  handle_t a = arena_create(LARGE, PAGE);
  (void)a;

  for (int round = 0; round < 64; round++) {
    handle_t sub = subarena_create();
    CHECK_MSG(sub != HANDLE_INVALID, "subarena_create in cycle");

    for (int k = 0; k < 8; k++) {
      handle_t h = arena_alloc(32);
      CHECK_MSG(h != HANDLE_INVALID, "alloc in subarena cycle");
      (void)h;
    }

    if (round % 2 == 0) {
      subarena_reset();
    } else {
      subarena_dealloc();
    }
  }
  CHECK_MSG(1, "subarena cycle stress completed without crash");

  arena_free();
}

static void test_stress_mixed_operations(void) {
  SUITE("stress: mixed arena/subarena/copy operations");

  handle_t outer = arena_create(LARGE, PAGE);

  for (int i = 0; i < 8; i++) {
    handle_t inner = arena_create(SMALL, PAGE);
    (void)inner;

    subarena_create();
    handle_t sh = arena_alloc(64);
    void *sp = resolve_handle(sh);
    memset(sp, (int)(i & 0xFF), 64);

    /* escape one allocation from sub into inner */
    subarena_escape(sh);

    /* copy from inner into outer */
    handle_t oh = arena_alloc(128);
    (void)oh;
    handle_t h_copied = arena_copy(outer, sh);
    CHECK_MSG(h_copied != HANDLE_INVALID,
              "arena_copy returns valid handle in mixed stress test");

    arena_free(); /* free inner */
    CHECK_MSG(resolve_handle(sh) == NULL, "inner handle dead after inner free");
  }

  arena_free(); /* free outer */
  CHECK_MSG(1, "mixed ops stress completed without crash");
}

/* -----------------------------------------------------------------------
 * 11. REGRESSION: double-free / double-reset guard
 * --------------------------------------------------------------------- */
static void test_double_reset_safe(void) {
  SUITE("regression: double arena_reset is safe");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;
  handle_t h = arena_alloc(64);
  arena_reset();
  CHECK_MSG(resolve_handle(h) == NULL, "dead after first reset");
  arena_reset(); /* must not crash or corrupt */
  CHECK_MSG(1, "second arena_reset does not crash");
  arena_free();
}

static void test_subarena_double_reset_safe(void) {
  SUITE("regression: double subarena_reset is safe");

  handle_t a = arena_create(SMALL, PAGE);
  (void)a;
  handle_t sub = subarena_create();
  (void)sub;
  arena_alloc(32);
  subarena_reset();
  subarena_reset(); /* second reset must not crash */
  CHECK_MSG(1, "double subarena_reset does not crash");
  subarena_dealloc();
  arena_free();
}

/* -----------------------------------------------------------------------
 * main
 * --------------------------------------------------------------------- */
int main(void) {
  printf("BAMM Runtime Test Suite\n");
  printf("========================\n");

  /* --- arena lifecycle --- */
  test_arena_lifecycle();
  test_arena_nested_stack();
  test_multiple_arena_cycles();

  /* --- alloc --- */
  test_alloc_basic();
  test_alloc_alignment();
  test_alloc_many();
  test_alloc_zero_size();
  test_alloc_exhaustion();

  /* --- reset --- */
  test_arena_reset();
  test_arena_reset_reuse();

  /* --- handle invalidation / UAF prevention --- */
  test_handle_dead_after_arena_free();
  test_handle_dead_after_nested_free();
  test_invalid_handle_constant();
  test_resolve_out_of_range();

  /* --- arena_copy --- */
  test_arena_copy_basic();
  test_arena_copy_noop_same_arena();
  test_arena_copy_independence();

  /* --- subarena --- */
  test_subarena_basic();
  test_subarena_reset();

  /* --- escape --- */
  test_subarena_escape_basic();
  test_subarena_escape_does_not_corrupt_parent();

  /* --- handle table --- */
  test_handle_metadata();
  test_handle_uniqueness();
  test_handle_table_capacity();

  /* --- dead handle --- */
  test_handle_dead();

  /* --- stress --- */
  test_stress_nested_alloc_free();
  test_stress_subarena_cycles();
  test_stress_mixed_operations();

  /* --- regressions --- */
  test_double_reset_safe();
  test_subarena_double_reset_safe();

  summary();
  return 0;
}
