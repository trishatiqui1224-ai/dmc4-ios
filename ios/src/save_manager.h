// Devil May Cry 4 iOS Port - Save Game & iCloud Container Manager
#pragma once

#import <Foundation/Foundation.h>
#include <filesystem>

namespace dmc4::save {

void InitializeSaveManager(const std::filesystem::path& docs_path);
bool SyncSavesWithiCloud();

} // namespace dmc4::save
