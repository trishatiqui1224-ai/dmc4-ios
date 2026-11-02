// Devil May Cry 4 iOS Port - Thread-Safe Stateless pread() ISO Piece Reader
#pragma once

#include <cstddef>
#include <cstdint>

namespace dmc4::vfs {

// Mounts an ISO image for thread-safe sector reading
bool MountIso(const char* iso_path);

// Unmounts the active ISO image
void UnmountIso();

// Reads data at byte_offset using stateless POSIX pread() with thread-safe sector caching
int64_t ReadIsoChunk(uint64_t byte_offset, void* destination, size_t byte_count);

// Returns true if an ISO is currently mounted
bool IsIsoMounted();

} // namespace dmc4::vfs
