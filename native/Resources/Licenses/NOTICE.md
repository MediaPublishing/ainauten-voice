# AInauten Voice third-party notices

FreeFlow v1.2.1 (`ce32cd5b88fc307ce193ba9ba1dac29d51a9f756`): MIT, copyright 2026 Zach Latta. The hold/toggle session controller is reused; AInauten Voice adds its own double-tap adapter.

FluidAudio v0.17.5 (`0b1f46289fe27d95b5e66ad8be46e64f5ee02ae7`): Apache 2.0. CoreML speech processing and conversion APIs.

SpeechRuntime.speechBearingPrefix adapts the pinned SDK's ChunkProcessor.speechEndSamples algorithm: trailing 80 ms frames below RMS 0.0005 are excluded only from inference length; original capture PCM is retained. Adaptation: preserve the original input if trimming would violate the public short decoder's 300 ms minimum. Source: https://github.com/FluidInference/FluidAudio/blob/v0.17.5/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/ChunkProcessor.swift . The algorithm is attributed to FluidAudio and covered by the included Apache 2.0 license. Experimental until its configuration is explicitly selected.

llama.cpp b11361: MIT. Embedded official XCFramework SHA256 `6f7684c7b00bdf13e4766d4a261471e5d6997dcfb3debfdf93afce3c0859942d`.

Parakeet multilingual model weights, converted by FluidInference, from NVIDIA Parakeet TDT 0.6B v3: CC BY 4.0 according to pinned Hugging Face metadata. https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe . This model license is distinct from the SDK license. Modifications: distribution of selected compiled CoreML files only, no model retraining. Credit NVIDIA and FluidInference.

Qwen3-4B-Instruct-2507, quantized by Unsloth to Q4_K_M: Apache 2.0. https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/tree/a06e946bb6b655725eafa393f4a9745d460374c9 . Credit Qwen/Alibaba and Unsloth.

Silero VAD v6.2.1, 256 ms CoreML conversion by FluidInference: MIT according to the pinned model card. https://huggingface.co/FluidInference/silero-vad-coreml/tree/b419383c55c110e2c9271fa6ee0ea83d03c70d96 . Credit Silero Team and FluidInference. Selected compiled model files are unmodified; their SHA256 digests are recorded in the model manifest. The upstream v6.2.1 MIT license is included as Silero-MIT.txt; source: https://github.com/snakers4/silero-vad/blob/v6.2.1/LICENSE .

Sparkle 2.9.1 (`066e75a8b3e9`): MIT. Signed automatic updates. The license is bundled as Sparkle-MIT.txt during packaging.

KSCrash 2.5.1 (`95a8895d75f3`): MIT. Local crash capture for the consent-based error report; no memory contents are recorded. License: KSCrash-MIT.txt.

uv 0.12.5 (Astral): MIT or Apache 2.0. Bundled only as the installer for the optional, disabled research feature; its license files are bundled next to it during packaging.

The executable package includes the original code licenses and pinned model cards. Models are downloaded separately after user initiation, with SHA256 verification. No model weights are committed to source control.
