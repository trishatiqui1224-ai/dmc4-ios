#pragma once
#include <cstdint>
#include <vector>

namespace dmc4::save {
bool VerifySaveChecksum(const uint8_t* data, size_t length);
}
