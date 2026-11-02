// Devil May Cry 4 iOS Port - Thread-Safe Stateless pread() ISO Piece Reader
// High-Throughput Chunked Streaming for MT Framework ARC Archives

#import <Foundation/Foundation.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <atomic>
#include <mutex>
#include <unordered_map>
#include <vector>

#include <rex/logging.h>

#include "iso_piece_reader.h"

namespace dmc4::vfs {

namespace {

int g_iso_fd = -1;
uint64_t g_iso_file_size = 0;
std::mutex g_iso_mutex;

// Sector Cache (2048-byte DVD sector size)
constexpr size_t kSectorSize = 2048;
constexpr size_t kCacheSlots = 512; // 1 MB cache
struct SectorCacheEntry {
    uint64_t sector_index = UINT64_MAX;
    uint8_t data[kSectorSize];
};

std::vector<SectorCacheEntry> g_sector_cache(kCacheSlots);
std::unordered_map<uint64_t, size_t> g_sector_map;
std::mutex g_cache_mutex;

} // namespace

bool MountIso(const char* iso_path) {
    if (!iso_path) return false;
    std::lock_guard<std::mutex> lock(g_iso_mutex);

    if (g_iso_fd >= 0) {
        close(g_iso_fd);
        g_iso_fd = -1;
    }

    g_iso_fd = open(iso_path, O_RDONLY);
    if (g_iso_fd < 0) {
        REXLOG_ERROR("[DMC4 VFS] Failed to open ISO file: {}", iso_path);
        return false;
    }

    struct stat st{};
    if (fstat(g_iso_fd, &st) == 0) {
        g_iso_file_size = st.st_size;
    }

    // Set thread QoS to User Initiated for fast decompression streaming
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);

    REXLOG_INFO("[DMC4 VFS] Successfully mounted ISO: {} ({} GB)", iso_path, g_iso_file_size / (1024.0 * 1024.0 * 1024.0));
    return true;
}

void UnmountIso() {
    std::lock_guard<std::mutex> lock(g_iso_mutex);
    if (g_iso_fd >= 0) {
        close(g_iso_fd);
        g_iso_fd = -1;
        g_iso_file_size = 0;
        REXLOG_INFO("[DMC4 VFS] Unmounted ISO file.");
    }
}

int64_t ReadIsoChunk(uint64_t byte_offset, void* destination, size_t byte_count) {
    if (g_iso_fd < 0 || !destination || byte_count == 0) return -1;

    // Stateless POSIX pread() eliminates file seek races across multi-threaded workers
    ssize_t bytes_read = pread(g_iso_fd, destination, byte_count, static_cast<off_t>(byte_offset));
    if (bytes_read < 0) {
        REXLOG_ERROR("[DMC4 VFS] pread failed at offset 0x{:X} for {} bytes: {}", byte_offset, byte_count, strerror(errno));
        return -1;
    }
    return bytes_read;
}

bool IsIsoMounted() {
    return g_iso_fd >= 0;
}

} // namespace dmc4::vfs
