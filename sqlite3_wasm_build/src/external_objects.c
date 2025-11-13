#include "external_objects.h"

#include <stdint.h>
#include <stdlib.h>

// A table of ExternalDartReference objects. When we want to call methods on
// them, we pass them as a first argument to a static entrypoint function
// injected when instantiating the module.
static __externref_t host_objects[0];

// Note: Inlining these functions seems to cause linker errors (something about
// clang attempting to take the address of host_objects).
void host_table_set(int index, __externref_t value) {
  __builtin_wasm_table_set(host_objects, index, value);
}

static __externref_t host_table_get(int index) {
  return __builtin_wasm_table_get(host_objects, index);
}

static int host_table_grow(int size) {
  return __builtin_wasm_table_grow(host_objects,
                                   __builtin_wasm_ref_null_extern(), size);
}

static int host_table_size() { return __builtin_wasm_table_size(host_objects); }

// A simple slab allocator to find free indices in the host objects table.
typedef struct {
  // Index of the next available slot in the slab, or set to capacity if full.
  size_t first_free_slot;
  // A capacity-length array storing indexing information.
  //
  // If host_object[i] is unoccupied, freelist[i] contains the next value for
  // first_free_slot after allocating in that slot. This effectively forms a
  // linked stack of free slots.
  //
  // If host_object[i] is occuped, the value of freelist[i] is unspecified.
  size_t* freelist;
} slab;

static slab host_objects_slab = {.first_free_slot = 0, .freelist = nullptr};

void* host_object_insert(__externref_t ref) {
  auto slot = host_objects_slab.first_free_slot;
  auto old_capacity = host_table_size();
  if (slot == old_capacity) {  // Table full?
    auto target_size = old_capacity * 2;
    if (target_size < 16) {
      // It's 0 initially, grow it to a reasonable initial size we're unlikely
      // to exceed.
      target_size = 16;
    }

    auto grow_result = host_table_grow(target_size);
    if (grow_result != old_capacity) {
      __builtin_trap();
    }

    size_t* freelist =
        realloc(host_objects_slab.freelist, target_size * sizeof(size_t));
    for (size_t i = old_capacity; i < target_size; i++) {
      freelist[i] = i + 1;
    }
    // Note: first_free_slot = old_capacity, freelist[old_capacity] =
    // old_capacity + 1 and so on.
    host_objects_slab.freelist = freelist;
    host_objects_slab.first_free_slot = slot + 1;
  } else {
    // Pop freelist.
    host_objects_slab.first_free_slot = host_objects_slab.freelist[slot];
  }

  // Persist reference into table.
  host_table_set(slot, ref);
  return (void*)slot;
}

__externref_t host_object_get(void* ptr) {
  size_t index = (size_t)ptr;
  return host_table_get(index);
}

void host_object_free(void* ptr) {
  size_t index = (size_t)ptr;

  // Remove external reference from table.
  host_table_set(index, __builtin_wasm_ref_null_extern());

  // Push index to front of freelist.
  host_objects_slab.freelist[index] = host_objects_slab.first_free_slot;
  host_objects_slab.first_free_slot = index;
}
