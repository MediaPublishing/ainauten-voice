<!-- Relative graph references resolved to the pinned upstream model card location. Model card text unchanged. -->
---
license: mit
tags:
- audio
- voice-activity-detection
- coreml
- silero
- speech
- ios
- macos
- swift
library_name: coreml
pipeline_tag: voice-activity-detection
datasets:
- alexwengg/musan_mini50
- alexwengg/musan_mini100
metrics:
- accuracy
- f1
language:
- en
base_model:
- onnx-community/silero-vad
---


# **<span style="color:#5DAF8D">🧃 CoreML Silero VAD </span>**
[![Discord](https://img.shields.io/badge/Discord-Join%20Chat-7289da.svg)](https://discord.gg/WNsvaCtmDe)
[![GitHub Repo stars](https://img.shields.io/github/stars/FluidInference/FluidAudio?style=flat&logo=github)](https://github.com/FluidInference/FluidAudio)

A CoreML implementation of the Silero Voice Activity
Detection (VAD) model, optimized for Apple platforms
(iOS/macOS). This repository contains pre-converted
CoreML models ready for use in Swift applications.

See FluidAudio Repo link at the top for more information

## Model Description

**Developed by:** Silero Team (original), converted by
FluidAudio

**Model type:** Voice Activity Detection

**License:** MIT

**Parent Model:**
[silero-vad](https://github.com/snakers4/silero-vad)


This is how the model performs against the silero-vad v6.0.0 basline Pytorch JIT version 

![graphs/yc_standard_comparison_20250915_205721_2c04b81.png](https://huggingface.co/FluidInference/silero-vad-coreml/resolve/b419383c55c110e2c9271fa6ee0ea83d03c70d96/graphs/yc_standard_comparison_20250915_205721_2c04b81.png)
![graphs/yc_256ms_comparison_20250915_205721_2c04b81.png](https://huggingface.co/FluidInference/silero-vad-coreml/resolve/b419383c55c110e2c9271fa6ee0ea83d03c70d96/graphs/yc_256ms_comparison_20250915_205721_2c04b81.png)

Note that we tested the quantized versions, as the model is already tiny, theres no performance imporvement at all. 


This is how the different models compare in terms of speed, the 256s takes in 8 chunks of 32ms and processes it in batches so its much faster
![graphs/yc_performance_20250915_205721_2c04b81.png](https://huggingface.co/FluidInference/silero-vad-coreml/resolve/b419383c55c110e2c9271fa6ee0ea83d03c70d96/graphs/yc_performance_20250915_205721_2c04b81.png)


Conversion code is available here: [FluidInference/mobius](https://github.com/FluidInference/mobius)

## Intended Use

### Primary Use Cases
- Real-time voice activity detection in iOS/macOS
applications
- Speech preprocessing for ASR systems
- Audio segmentation and filtering

## How to Use

Citation

@misc{silero-vad-coreml,
  title={CoreML Silero VAD},
  author={FluidAudio Team},
  year={2024},

url={https://huggingface.co/alexwengg/coreml-silero-vad}
}

@misc{silero-vad,
  title={Silero VAD},
  author={Silero Team},
  year={2021},
  url={https://github.com/snakers4/silero-vad}
}


- GitHub: https://github.com/FluidAudio/FluidAudioSwift

