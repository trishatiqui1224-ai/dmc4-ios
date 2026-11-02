// Devil May Cry 4 (Title ID: 434307DF) - iOS Launcher
#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#endif

#include <filesystem>
#include <string>
#include <vector>

namespace dmc4::launcher {

// Locates the app's Documents folder
std::filesystem::path Documents();

// Discovers ISO or game folder in Documents/
std::vector<std::filesystem::path> FindGameFiles(const std::filesystem::path& documents);

// Shows the pre-launch settings UI and enters the game when Start is tapped
void ShowLauncher(int argc, char* argv[], std::vector<std::string>& game_args, const std::filesystem::path& game_path);

// Retrieves user configured runtime arguments
std::vector<std::string> GetConfiguredArguments(const std::filesystem::path& documents);

} // namespace dmc4::launcher
