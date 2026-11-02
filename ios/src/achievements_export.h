#pragma once
#include <filesystem>

namespace dmc4::achievements {
void ExportAchievementsToJson(const std::filesystem::path& json_path);
}
