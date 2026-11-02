// Devil May Cry 4 (Title ID: 434307DF) - Game Application Core
#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace dmc4::app {

// Launches the recompiled Devil May Cry 4 game
int RunGame(const std::vector<std::string>& args, const std::filesystem::path& game_path);

} // namespace dmc4::app
