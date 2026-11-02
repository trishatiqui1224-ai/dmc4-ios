#include <fstream>
#include <rex/logging.h>
#include "achievements_export.h"

namespace dmc4::achievements {

void ExportAchievementsToJson(const std::filesystem::path& json_path) {
    std::ofstream out(json_path);
    out << "{\n  \"title_id\": \"434307DF\",\n  \"game\": \"Devil May Cry 4\",\n  \"achievements\": []\n}\n";
    REXLOG_INFO("[DMC4 Achievements] Exported achievements template to: {}", json_path.string());
}

} // namespace dmc4::achievements
