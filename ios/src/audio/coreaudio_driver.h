// Devil May Cry 4 iOS Port - CoreAudio Low-Latency Driver
#pragma once

#include <cstddef>
#include <cstdint>

namespace dmc4::audio {

bool InitializeCoreAudio(uint32_t sample_rate = 48000, uint32_t channels = 2);
void ShutdownCoreAudio();
void WriteAudioSamples(const float* samples, size_t frame_count);

} // namespace dmc4::audio
