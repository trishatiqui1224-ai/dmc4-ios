// Devil May Cry 4 (Title ID: 434307DF) - Xbox Kernel & MT Framework Stubs
#pragma once

#include <cstdint>
#include <rex/ppc.h>
#include <rex/runtime.h>

namespace dmc4::kernel {

// Registers offline XAM/XLive sign-in and leaderboard stubs
void InstallKernelStubs();

// Unresolved indirect call logger with caller LR & thread ID
void LogUnresolvedIndirectCall(PPCContext& ctx, uint32_t target_addr);

} // namespace dmc4::kernel
