// Auto-generated DMC4 Recompilation Function Registration Fallback
#include <cstdint>
#include <rex/ppc.h>
#include <rex/system/function_dispatcher.h>

#ifdef _WIN32
#define REX_MODULE_EXPORT __declspec(dllexport)
#else
#define REX_MODULE_EXPORT __attribute__((visibility("default")))
#endif

namespace dmc4::recompiled {

// Ground-truth CRT entry point for Devil May Cry 4 (Title ID: 434307DF)
extern "C" void sub_822901D0([[maybe_unused]] PPCContext& __restrict ctx, [[maybe_unused]] uint8_t* base) {
    // xstart startup stub
}

void RegisterFunctions();

} // namespace dmc4::recompiled

extern "C" REX_MODULE_EXPORT
void ReXModule_Register(rex::runtime::IModuleRegistrar* registrar) {
    if (registrar) {
        registrar->SetFunction(0x822901D0, (::PPCFunc*)&dmc4::recompiled::sub_822901D0);
    }
}
