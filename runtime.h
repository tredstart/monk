#ifndef RUNTIME_H
#define RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MAX_HANDLES 100000
#define HANDLE_INVALID (MAX_HANDLES + 64)

extern int    bamm_argc;
extern char **bamm_argv;
void bamm_init(int argc, char **argv);

typedef size_t handle_t;

// resolve a handle to a raw pointer, returns NULL if dead
void *resolve_handle(handle_t handle);

// handle metadata accessors
uint64_t handle_get_id(handle_t handle);
handle_t handle_get_arena(handle_t handle);
size_t handle_get_size(handle_t handle);
bool handle_is_alive(handle_t handle);

// --- arena ---
handle_t arena_create(size_t reserve_size, size_t page_size);
handle_t arena_alloc(size_t size);
void arena_free();
void arena_reset();
handle_t arena_copy(handle_t dest_arena_handle, handle_t obj_handle);

// --- subarena ---
handle_t subarena_create();
void subarena_dealloc();
void subarena_reset();
void subarena_escape(handle_t handle);

#endif // RUNTIME_H
