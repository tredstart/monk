#include "runtime.h"
#include <assert.h>
#include <string.h>
#include <sys/mman.h>

#ifdef HAS_VALGRIND
#include <valgrind/memcheck.h>
#else
#define VALGRIND_MALLOCLIKE_BLOCK(addr, size, rz, is_zeroed) ((void)0)
#define VALGRIND_FREELIKE_BLOCK(addr, rz) ((void)0)
#define VALGRIND_MAKE_MEM_DEFINED(addr, size) ((void)0)
#endif

typedef enum {
  F_CREATE_BLOCK = MAX_HANDLES + 1,
  F_MEM_RESERVE,
} ARENA_ERROR_CODES;

typedef struct {
  uint64_t id;
  void *addr; // NULL = dead
  handle_t arena;
  size_t size;
  bool pinned; // Rule 10, reserved
} handle_entry_t;

typedef struct arena_t {
  size_t parent_handle;
  size_t page_size, reserved_size, commited_size, current_offset;
  uint8_t *base;
} arena_t;

typedef struct {
  size_t parent_handle;
  size_t og_offset;
} subarena_t;

typedef struct {
  handle_t current_arena_handle;
  handle_t current_subarena_handle;
} context_t;

static handle_entry_t handle_table[MAX_HANDLES] = {0};
static size_t next_handle = 0;
static uint64_t next_id = 1;

// ---- handle API -----------------------------------------------------------

uint64_t handle_get_id(handle_t handle) {
  assert(handle < next_handle);
  return handle_table[handle].id;
}

handle_t handle_get_arena(handle_t handle) {
  assert(handle < next_handle);
  return handle_table[handle].arena;
}

size_t handle_get_size(handle_t handle) {
  assert(handle < next_handle);
  return handle_table[handle].size;
}

bool handle_is_alive(handle_t handle) {
  if (handle >= next_handle)
    return false;
  return handle_table[handle].addr != NULL;
}

void *resolve_handle(handle_t handle) {
  if (handle >= MAX_HANDLES)
    return NULL;
  return handle_table[handle].addr;
}

static inline void invalidate_handles_in_range(uint8_t *base, size_t from,
                                               size_t to) {
  for (size_t i = 0; i < next_handle; i++) {
    uint8_t *p = handle_table[i].addr;
    if (p >= base + from && p < base + to) {
      if (p != NULL) {
        memset(p, 0, handle_table[i].size);
        VALGRIND_FREELIKE_BLOCK(p, 0);
      }
      handle_table[i].addr = NULL;
    }
  }
}

static inline handle_t alloc_handle(void *ptr, handle_t arena, size_t size) {
  if (next_handle >= MAX_HANDLES)
    return HANDLE_INVALID;
  handle_t h = next_handle++;
  handle_table[h] = (handle_entry_t){
      .id = next_id++,
      .addr = ptr,
      .arena = arena,
      .size = size,
      .pinned = false,
  };
  return h;
}

__thread context_t context = {
    .current_arena_handle = HANDLE_INVALID,
    .current_subarena_handle = HANDLE_INVALID,
};

static inline size_t align_to_page(size_t page_size, size_t size) {
  return (size + page_size - 1) / page_size * page_size;
}

// ---- arena lifecycle ------------------------------------------------------

handle_t arena_create(size_t reserve_size, size_t page_size) {
  size_t header_size = align_to_page(page_size, sizeof(arena_t));
  reserve_size = align_to_page(page_size, reserve_size);
  size_t total_reserve = reserve_size + header_size;

  uint8_t *base =
      mmap(NULL, total_reserve, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (base == MAP_FAILED)
    return F_CREATE_BLOCK;

  if (mprotect(base, header_size, PROT_READ | PROT_WRITE) != 0) {
    munmap(base, total_reserve);
    return F_MEM_RESERVE;
  }

  arena_t *ar = (arena_t *)base;
  VALGRIND_MALLOCLIKE_BLOCK(ar, header_size, 0, 0);

  ar->base = base;
  ar->parent_handle = context.current_arena_handle;
  ar->page_size = page_size;
  ar->reserved_size = total_reserve;
  ar->commited_size = header_size;
  ar->current_offset = header_size;

  handle_t h = alloc_handle(ar, HANDLE_INVALID, header_size);
  if (h == HANDLE_INVALID) {
    munmap(base, total_reserve);
    return HANDLE_INVALID;
  }

  context.current_arena_handle = h;
  return h;
}

void arena_free() {
  assert(context.current_arena_handle != HANDLE_INVALID);

  arena_t *a = resolve_handle(context.current_arena_handle);
  if (a) {
    size_t parent_handle = a->parent_handle;
    void *base = a->base;
    size_t reserved_size = a->reserved_size;
    invalidate_handles_in_range(base, 0, reserved_size);
    munmap(base, reserved_size);
    context.current_arena_handle = parent_handle;

    if (context.current_subarena_handle != HANDLE_INVALID &&
        !resolve_handle(context.current_subarena_handle)) {
      context.current_subarena_handle = HANDLE_INVALID;
    }
  }
}

void arena_reset() {
  assert(context.current_arena_handle != HANDLE_INVALID);

  arena_t *ar = resolve_handle(context.current_arena_handle);
  if (!ar)
    return;

  size_t header_size = align_to_page(ar->page_size, sizeof(arena_t));
  invalidate_handles_in_range(ar->base, header_size, ar->current_offset);
  ar->current_offset = header_size;
}

// ---- arena alloc ----------------------------------------------------------

handle_t arena_alloc(size_t size) {
  assert(context.current_arena_handle != HANDLE_INVALID);
  if (size == 0)
    return HANDLE_INVALID;

  arena_t *ar = resolve_handle(context.current_arena_handle);
  assert(ar != NULL);

  size_t new_offset = ar->current_offset + size;
  if (new_offset > ar->reserved_size)
    return HANDLE_INVALID;

  if (new_offset > ar->commited_size) {
    size_t new_commit_target = align_to_page(ar->page_size, new_offset);
    if (new_commit_target > ar->reserved_size)
      new_commit_target = ar->reserved_size;

    size_t to_commit = new_commit_target - ar->commited_size;
    if (mprotect(ar->base + ar->commited_size, to_commit,
                 PROT_READ | PROT_WRITE) != 0)
      return HANDLE_INVALID;

    ar->commited_size = new_commit_target;
  }

  void *ptr = ar->base + ar->current_offset;
  ar->current_offset = new_offset;

  handle_t h = alloc_handle(ptr, context.current_arena_handle, size);
  if (h == HANDLE_INVALID) {
    ar->current_offset -= size;
    return HANDLE_INVALID;
  }

  VALGRIND_MALLOCLIKE_BLOCK(ptr, size, 0, 0);
  return h;
}

// ---- subarena -------------------------------------------------------------

handle_t subarena_create() {
  assert(context.current_arena_handle != HANDLE_INVALID);

  arena_t *ar = resolve_handle(context.current_arena_handle);
  assert(ar != NULL);

  size_t saved_offset = ar->current_offset;
  handle_t sub_index = arena_alloc(sizeof(subarena_t));
  if (sub_index == HANDLE_INVALID)
    return HANDLE_INVALID;

  subarena_t *sub = resolve_handle(sub_index);
  sub->parent_handle = context.current_arena_handle;
  sub->og_offset = saved_offset;
  context.current_subarena_handle = sub_index;

  return sub_index;
}

void subarena_dealloc() {
  assert(context.current_subarena_handle != HANDLE_INVALID);

  subarena_t *sub = resolve_handle(context.current_subarena_handle);
  if (!sub)
    return;

  arena_t *parent = resolve_handle(sub->parent_handle);
  if (!parent)
    return;

  size_t og_offset = sub->og_offset;
  invalidate_handles_in_range(parent->base, og_offset, parent->current_offset);
  parent->current_offset = og_offset;
  context.current_subarena_handle = HANDLE_INVALID;
}

void subarena_reset() {
  assert(context.current_subarena_handle != HANDLE_INVALID);

  subarena_t *sub = resolve_handle(context.current_subarena_handle);
  if (!sub)
    return;

  arena_t *parent = resolve_handle(sub->parent_handle);
  if (!parent)
    return;

  size_t frame_start = sub->og_offset + sizeof(subarena_t);
  invalidate_handles_in_range(parent->base, frame_start,
                              parent->current_offset);
  parent->current_offset = frame_start;
}

void subarena_escape(handle_t handle) {
  assert(context.current_subarena_handle != HANDLE_INVALID);

  subarena_t *sub = resolve_handle(context.current_subarena_handle);
  assert(sub != NULL);

  void *old_ptr = resolve_handle(handle);
  assert(old_ptr != NULL);

  size_t size = handle_get_size(handle);

  arena_t *parent = resolve_handle(sub->parent_handle);
  assert(parent != NULL);

  size_t og_offset = sub->og_offset;
  void *new_ptr = parent->base + og_offset;

  // Kill all subarena handles first (zeroes their memory), so the memmove
  // below lands into clean space without corrupting the escaping object.
  for (size_t i = 0; i < next_handle; i++) {
    uint8_t *p = handle_table[i].addr;
    if (p >= parent->base + og_offset &&
        p < parent->base + parent->current_offset) {
      if (p != NULL && i != handle) {
        memset(p, 0, handle_table[i].size);
        VALGRIND_FREELIKE_BLOCK(p, 0);
        handle_table[i].addr = NULL;
      }
    }
  }

  // Tell Valgrind both regions are about to be repurposed
  VALGRIND_MAKE_MEM_DEFINED(old_ptr, size);
  VALGRIND_MAKE_MEM_DEFINED(new_ptr, size);

  // Now move the escaping data over the bookkeeping header we just killed
  memmove(new_ptr, old_ptr, size);

  VALGRIND_FREELIKE_BLOCK(old_ptr, 0);
  VALGRIND_MALLOCLIKE_BLOCK(new_ptr, size, 0, 0);
  VALGRIND_MAKE_MEM_DEFINED(new_ptr, size);

  handle_table[handle].addr = new_ptr;

  parent->current_offset = og_offset + size;
  size_t assigned_pages =
      align_to_page(parent->page_size, parent->current_offset);
  if (assigned_pages > parent->commited_size)
    parent->commited_size = assigned_pages;

  context.current_subarena_handle = HANDLE_INVALID;
}

// ---- arena copy (cross-arena) ---------------------------------------------

handle_t arena_copy(handle_t dest_arena_handle, handle_t obj_handle) {
  arena_t *dest_arena = resolve_handle(dest_arena_handle);
  assert(dest_arena != NULL);

  void *obj = resolve_handle(obj_handle);
  assert(obj != NULL);

  size_t size = handle_get_size(obj_handle);

  uint8_t *obj_p = (uint8_t *)obj;
  if (obj_p >= dest_arena->base &&
      obj_p < dest_arena->base + dest_arena->reserved_size)
    return obj_handle;

  size_t new_offset = dest_arena->current_offset + size;
  if (new_offset > dest_arena->reserved_size)
    return HANDLE_INVALID;

  if (new_offset > dest_arena->commited_size) {
    size_t new_commit_target = align_to_page(dest_arena->page_size, new_offset);
    if (new_commit_target > dest_arena->reserved_size)
      new_commit_target = dest_arena->reserved_size;

    size_t to_commit = new_commit_target - dest_arena->commited_size;
    mprotect(dest_arena->base + dest_arena->commited_size, to_commit,
             PROT_READ | PROT_WRITE);
    dest_arena->commited_size = new_commit_target;
  }

  void *dest_ptr = dest_arena->base + dest_arena->current_offset;

  handle_t new_handle = alloc_handle(dest_ptr, dest_arena_handle, size);
  if (new_handle == HANDLE_INVALID)
    return HANDLE_INVALID;

  VALGRIND_MALLOCLIKE_BLOCK(dest_ptr, size, 0, 0);
  memcpy(dest_ptr, obj, size);
  dest_arena->current_offset = new_offset;

  return new_handle;
}
