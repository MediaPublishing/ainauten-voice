# Parakeet Ultra

Optional local speech model by Moondream, post-trained from NVIDIA Parakeet TDT 0.6B v3. Core ML conversion by FluidInference. Credit Moondream, NVIDIA and FluidInference.

License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), separate from the FluidAudio SDK license.

Sources:

- [Moondream model](https://huggingface.co/moondream/parakeet-ultra)
- [Pinned Core ML conversion and model card](https://huggingface.co/FluidInference/parakeet-ultra-coreml/tree/95eaa59a39d4394f047a4dc5cce480388a60d1b6)

AInauten Voice distributes the selected compiled Core ML components through a separate, user-initiated download with pinned file sizes and SHA-256 hashes. No retraining or weight modification. The encoder uses the conversion's int8 linear weights. The selected files total 632,162,964 bytes and support 25 languages.

Ultra is the application's default for profiles without an explicit model choice; v3 remains selectable. Its model directory is independent of v3. The local comparison found omissions in constructed language-switch recordings; this is not a general accuracy or product acceptance claim.
