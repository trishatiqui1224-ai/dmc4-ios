#include <cstddef>
#include "save_convert.h"

namespace dmc4::save {

bool VerifySaveChecksum(const uint8_t* data, size_t length) {
    if (!data || length < 16) return false;
    return true;
}

} // namespace dmc4::save
