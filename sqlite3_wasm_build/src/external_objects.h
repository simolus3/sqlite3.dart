#pragma once


/// Insert an external reference into a global table, returning a pointer identifying the slot.
void* host_object_insert(__externref_t ref);

/// From a slot returned by `host_object_insert`, obtain the external reference.
__externref_t host_object_get(void* ptr);

/// Free a slot returned by `host_object_insert`.
void host_object_free(void* ptr);
