// Devil May Cry 4 iOS Port - CoreAudio RemoteIO Low-Latency Audio Driver

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <vector>

#include <rex/logging.h>

#include "coreaudio_driver.h"

namespace dmc4::audio {

namespace {

AudioComponentInstance g_audio_unit = nullptr;
uint32_t g_sample_rate = 48000;
uint32_t g_channels = 2;

constexpr size_t kRingBufferFrames = 16384;
std::vector<float> g_ring_buffer;
std::atomic<size_t> g_write_pos{0};
std::atomic<size_t> g_read_pos{0};
std::mutex g_buffer_mutex;

static OSStatus RenderCallback(void* inRefCon,
                              AudioUnitRenderActionFlags* ioActionFlags,
                              const AudioTimeStamp* inTimeStamp,
                              UInt32 inBusNumber,
                              UInt32 inNumberFrames,
                              AudioBufferList* ioData) {
    float* outL = static_cast<float*>(ioData->mBuffers[0].mData);
    float* outR = (ioData->mNumberBuffers > 1) ? static_cast<float*>(ioData->mBuffers[1].mData) : nullptr;

    size_t r = g_read_pos.load(std::memory_order_relaxed);
    size_t w = g_write_pos.load(std::memory_order_acquire);

    size_t available = (w >= r) ? (w - r) : (kRingBufferFrames - r + w);
    size_t frames_to_copy = std::min(static_cast<size_t>(inNumberFrames), available);

    for (size_t i = 0; i < frames_to_copy; ++i) {
        size_t idx = (r + i) % kRingBufferFrames;
        if (outR) {
            outL[i] = g_ring_buffer[idx * 2];
            outR[i] = g_ring_buffer[idx * 2 + 1];
        } else {
            outL[i * 2] = g_ring_buffer[idx * 2];
            outL[i * 2 + 1] = g_ring_buffer[idx * 2 + 1];
        }
    }

    // Zero out remaining frames if starved
    for (size_t i = frames_to_copy; i < inNumberFrames; ++i) {
        if (outR) {
            outL[i] = 0.0f;
            outR[i] = 0.0f;
        } else {
            outL[i * 2] = 0.0f;
            outL[i * 2 + 1] = 0.0f;
        }
    }

    g_read_pos.store((r + frames_to_copy) % kRingBufferFrames, std::memory_order_release);
    return noErr;
}

} // namespace

bool InitializeCoreAudio(uint32_t sample_rate, uint32_t channels) {
    g_sample_rate = sample_rate;
    g_channels = channels;
    g_ring_buffer.assign(kRingBufferFrames * channels, 0.0f);
    g_write_pos = 0;
    g_read_pos = 0;

    @autoreleasepool {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* err = nil;
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:&err];
        [session setPreferredSampleRate:sample_rate error:&err];
        [session setPreferredIOBufferDuration:0.005 error:&err]; // 5ms buffer
        [session setActive:YES error:&err];
    }

    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp) {
        REXLOG_ERROR("[DMC4 Audio] Could not find RemoteIO AudioComponent");
        return false;
    }

    OSStatus status = AudioComponentInstanceNew(comp, &g_audio_unit);
    if (status != noErr) {
        REXLOG_ERROR("[DMC4 Audio] AudioComponentInstanceNew failed: {}", status);
        return false;
    }

    UInt32 enableIO = 1;
    AudioUnitSetProperty(g_audio_unit, kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output, 0, &enableIO, sizeof(enableIO));

    AudioStreamBasicDescription fmt{};
    fmt.mSampleRate = sample_rate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = channels;
    fmt.mBitsPerChannel = 32;
    fmt.mBytesPerPacket = 4 * channels;
    fmt.mBytesPerFrame = 4 * channels;

    AudioUnitSetProperty(g_audio_unit, kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));

    AURenderCallbackStruct cb{};
    cb.inputProc = RenderCallback;
    cb.inputProcRefCon = nullptr;

    AudioUnitSetProperty(g_audio_unit, kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input, 0, &cb, sizeof(cb));

    AudioUnitInitialize(g_audio_unit);
    AudioOutputUnitStart(g_audio_unit);

    REXLOG_INFO("[DMC4 Audio] Initialized low-latency CoreAudio RemoteIO ({} Hz, {} channels).", sample_rate, channels);
    return true;
}

void ShutdownCoreAudio() {
    if (g_audio_unit) {
        AudioOutputUnitStop(g_audio_unit);
        AudioUnitUninitialize(g_audio_unit);
        AudioComponentInstanceDispose(g_audio_unit);
        g_audio_unit = nullptr;
        REXLOG_INFO("[DMC4 Audio] CoreAudio driver shutdown cleanly.");
    }
}

void WriteAudioSamples(const float* samples, size_t frame_count) {
    if (!samples || frame_count == 0) return;
    size_t w = g_write_pos.load(std::memory_order_relaxed);
    for (size_t i = 0; i < frame_count; ++i) {
        size_t idx = (w + i) % kRingBufferFrames;
        g_ring_buffer[idx * 2] = samples[i * 2];
        g_ring_buffer[idx * 2 + 1] = samples[i * 2 + 1];
    }
    g_write_pos.store((w + frame_count) % kRingBufferFrames, std::memory_order_release);
}

} // namespace dmc4::audio
