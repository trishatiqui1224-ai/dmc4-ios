// Devil May Cry 4 iOS Port - Save Import & Achievements Export
#pragma once

#include <filesystem>
#include <string>

namespace dmc4::save {
bool ImportExternalSave(const std::filesystem::path& src, const std::filesystem::path& dest);
} // namespace dmc4::save

namespace dmc4::achievements {
void ExportUnlockedAchievements(const std::filesystem::path& out_json);
} // namespace dmc4::achievements
