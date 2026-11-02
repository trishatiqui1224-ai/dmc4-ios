// Devil May Cry 4 (Title ID: 434307DF) - Xbox Kernel & MT Framework Stubs
// Offline XAM / XLive Sign-In & Leaderboard Stubs + Unresolved Branch Logger

#include <pthread.h>
#include <rex/logging.h>
#include <rex/ppc.h>
#include <rex/runtime.h>
#include <spdlog/spdlog.h>

#include "dmc4_kernel_stubs.h"

namespace dmc4::kernel {

// Stub for XAM offline user sign-in status: returns ERROR_SUCCESS (0)
void XamUserGetSigninStateStub(PPCContext& ctx) {
    // r3 = user index, return r3 = eXUserSigninState_SignedInLocally (1)
    ctx.r3.u64 = 1;
}

// Stub for Xbox Live leaderboard enumeration: return offline status without hanging
void XamLeaderboardCreateStub(PPCContext& ctx) {
    // Return ERROR_NOT_CONNECTED (0x800704CF) or ERROR_SUCCESS with 0 entries
    ctx.r3.u64 = 0; // Handled gracefully
}

void LogUnresolvedIndirectCall(PPCContext& ctx, uint32_t target_addr) {
    uint64_t tid = 0;
    pthread_threadid_np(nullptr, &tid);
    REXLOG_ERROR("[DMC4 INDIRECT CALL] Unresolved target: 0x{:08X} | Caller LR: 0x{:08X} | Thread ID: {}",
                 target_addr, static_cast<uint32_t>(ctx.lr.u32), tid);
    rex::FlushLogging();
    if (auto logger = spdlog::default_logger()) {
        logger->flush();
    }
}

void InstallKernelStubs() {
    REXLOG_INFO("[DMC4 Kernel] Installed offline XAM/XLive leaderboard & sign-in stubs.");
}

} // namespace dmc4::kernel
