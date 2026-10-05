---
license: cc-by-4.0
track_downloads: true
language:
- en
- es
- fr
- de
- bg
- hr
- cs
- da
- nl
- et
- fi
- el
- hu
- it
- lv
- lt
- mt
- pl
- pt
- ro
- sk
- sl
- sv
- ru
- uk
pipeline_tag: automatic-speech-recognition
library_name: nemo
datasets:
- nvidia/Granary
- nemo/asr-set-3.0
thumbnail: null
tags:
- automatic-speech-recognition
- speech
- audio
- Transducer
- TDT
- FastConformer
- Conformer
- pytorch
- NeMo
- hf-asr-leaderboard
widget:
- example_title: Librispeech sample 1
  src: https://cdn-media.huggingface.co/speech_samples/sample1.flac
- example_title: Librispeech sample 2
  src: https://cdn-media.huggingface.co/speech_samples/sample2.flac
base_model:
- nvidia/parakeet-tdt-0.6b-v3
---

# **<span style="color:#5DAF8D"> 🧃 parakeet-tdt-0.6b-v3: Multilingual Speech-to-Text Model CoreML </span>**

<style>
img {
 display: inline;
}
</style>

[![Model architecture](https://img.shields.io/badge/Model_Arch-FastConformer--TDT-blue#model-badge)](#model-architecture)
| [![Model size](https://img.shields.io/badge/Params-0.6B-green#model-badge)](#model-architecture)
| [![Language](https://img.shields.io/badge/Language-EU_Languages-blue#model-badge)](#datasets)
| [![Discord](https://img.shields.io/badge/Discord-Join%20Chat-7289da.svg)](https://discord.gg/WNsvaCtmDe)
| [![GitHub Repo stars](https://img.shields.io/github/stars/FluidInference/FluidAudio?style=flat&logo=github)](https://github.com/FluidInference/FluidAudio)

On‑device multilingual ASR model converted to Core ML for Apple platforms. This model powers FluidAudio’s batch ASR and is the same model used in our backend. It supports 25 European languages and is optimized for low‑latency, private, offline transcription.



The conversion script is here:
https://github.com/FluidInference/mobius/tree/main/models/stt/parakeet-tdt-v3-0.6b/coreml 

And the benchmarks are here:
https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md#transcription 


## Highlights

- **Core ML**: Runs fully on‑device (ANE/CPU) on Apple Silicon.
- **Multilingual**: 25 European languages; see model usage in FluidAudio for examples.
- **Performance**: ~110× RTF on M4 Pro for batch ASR (1 min audio ≈ 0.5 s).
- **Privacy**: No network calls required once models are downloaded.

## Intended Use

- **Batch transcription** of complete audio files on macOS/iOS.
- **Local dictation** and note‑taking apps where privacy and latency matter.
- **Embedded ASR** in production apps via the FluidAudio Swift framework.

## Supported Platforms

- macOS 14+ (Apple Silicon recommended)
- iOS 17+

## Model Details

- **Architecture**: Parakeet TDT v3 (Token Duration Transducer, 0.6B parameters)
- **Input audio**: 16 kHz, mono, Float32 PCM in range [-1, 1]
- **Languages**: 25 European languages (multilingual)
- **Precision**: Mixed precision optimized for Core ML execution (ANE/CPU)

## Performance

- **Real‑time factor (RTF)**: ~110× on M4 Pro in batch mode
- Throughput and latency vary with device, input duration, and compute units (ANE/CPU).

## Usage

For quickest integration, use the FluidAudio Swift framework which handles model loading, audio preprocessing, and decoding.

### Swift (FluidAudio)

```swift
import AVFoundation
import FluidAudio

Task {
    // Download and load ASR models (first run only)
    let models = try await AsrModels.downloadAndLoad()

    // Initialize ASR manager with default config
    let asr = AsrManager(config: .default)
    try await asr.initialize(models: models)

    // Load audio and transcribe
    let samples = try await AudioProcessor.loadAudioFile(path: "path/to/audio.wav")
    let result = try await asr.transcribe(samples, source: .system)
    print(result.text)

    asr.cleanup()
}
```

For more examples (including CLI usage and benchmarking), see the FluidAudio repository: https://github.com/FluidInference/FluidAudio

## Files

- Core ML model artifacts suitable for use via the FluidAudio APIs (preferred) or directly with Core ML.
- Tokenizer and configuration assets are included/managed by FluidAudio’s loaders.

## Limitations

- Primary coverage is European languages; performance may degrade for non‑European languages.

## License

Apache 2.0. See the FluidAudio repository for details and usage guidance.