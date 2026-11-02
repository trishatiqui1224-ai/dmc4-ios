#include <fstream>
#include <rex/logging.h>
#include "save_import.h"

namespace dmc4::save {

bool ImportExternalSave(const std::filesystem::path& src, const std::filesystem::path& dest) {
    std::error_code ec;
    std::filesystem::copy_file(src, dest, std::filesystem::copy_options::overwrite_existing, ec);
    if (!ec) {
        REXLOG_INFO("[DMC4 Save] Imported external save from {} -> {}", src.filename().string(), dest.string());
        return true;
    }
    return false;
}

} // namespace dmc4::save
