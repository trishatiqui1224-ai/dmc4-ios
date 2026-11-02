// Devil May Cry 4 iOS Port - Save Game & iCloud Container Manager

#import <Foundation/Foundation.h>
#include <filesystem>
#include <rex/logging.h>
#include "save_manager.h"

namespace dmc4::save {

static std::filesystem::path g_save_dir;

void InitializeSaveManager(const std::filesystem::path& docs_path) {
    g_save_dir = docs_path / "saves";
    std::error_code ec;
    std::filesystem::create_directories(g_save_dir, ec);
    REXLOG_INFO("[DMC4 Save] Save manager initialized at: {}", g_save_dir.string());
}

bool SyncSavesWithiCloud() {
    // Optional iCloud ubiquity container sync
    return true;
}

} // namespace dmc4::save
