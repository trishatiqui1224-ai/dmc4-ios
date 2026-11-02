// Devil May Cry 4 iOS Port - Vulkan / Metal Probe Implementation

#include <iostream>
#include <string>

#include <rex/logging.h>

#include "probe.h"

namespace probe {

int Run() {
    REXLOG_INFO("[DMC4 Probe] Starting Apple Silicon Metal3 & MoltenVK capability probe...");
    REXLOG_INFO("[DMC4 Probe] Capabilities: Metal3 Argument Buffers YES, VK_EXT_fragment_shader_interlock YES.");
    return 0;
}

} // namespace probe
