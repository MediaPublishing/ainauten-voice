#include "whisper.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

// Private stdin/stdout protocol: 16 kHz float PCM in RAM, bounded JSON out.
// No files, network, prompts, translation or SDK transcript logging.
static void quiet(enum ggml_log_level, const char *, void *) {}
static std::string json(const std::string &s) {
    std::string out = "\"";
    for (unsigned char c : s) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else if (c >= 32) out += c;
    }
    return out + '"';
}
struct Word { std::string text; double start, end; };
int main(int argc, char **argv) {
    if (argc == 2 && std::string(argv[1]) == "--version") { std::cout << "whisper.cpp 1.9.2\n"; return 0; }
    if (argc != 3 || (std::string(argv[2]) != "auto" && whisper_lang_id(argv[2]) < 0)) return 2;
    whisper_log_set(quiet, nullptr);
    ggml_log_set(quiet, nullptr);
    std::vector<float> pcm;
    float block[4096];
    while (std::cin) {
        std::cin.read(reinterpret_cast<char *>(block), sizeof(block));
        auto n = std::cin.gcount();
        if (n % sizeof(float) || pcm.size() + n / sizeof(float) > 16000 * 1200) return 3;
        pcm.insert(pcm.end(), block, block + n / sizeof(float));
    }
    if (pcm.size() < 4800) return 3;
    auto config = whisper_context_default_params();
    config.use_gpu = true;
    auto ctx = whisper_init_from_file_with_params(argv[1], config);
    if (!ctx || !whisper_is_multilingual(ctx)) { if (ctx) whisper_free(ctx); return 4; }
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.language = argv[2]; params.translate = false; params.detect_language = false;
    params.n_threads = 4; params.no_context = true;
    params.print_realtime = false; params.print_progress = false;
    params.print_timestamps = false; params.print_special = false;
    params.token_timestamps = true; params.temperature_inc = 0;
    if (whisper_full(ctx, params, pcm.data(), static_cast<int>(pcm.size()))) { whisper_free(ctx); return 5; }
    std::string text; std::vector<Word> words;
    for (int s = 0; s < whisper_full_n_segments(ctx); ++s) {
        text += whisper_full_get_segment_text(ctx, s);
        std::string word; double start = 0, end = 0;
        auto flush = [&] { if (!word.empty()) words.push_back({word, start, end}); word.clear(); };
        for (int t = 0; t < whisper_full_n_tokens(ctx, s); ++t) {
            auto data = whisper_full_get_token_data(ctx, s, t);
            if (data.id >= whisper_token_eot(ctx)) continue;
            std::string token = whisper_full_get_token_text(ctx, s, t);
            // Byte pieces are accumulated before UTF-8 is emitted, preserving umlauts.
            for (unsigned char c : token) {
                if (c == ' ' || c == '\n' || c == '\t') flush();
                else { if (word.empty()) start = std::max<int64_t>(0, data.t0) / 100.; word += c; end = std::max(start, data.t1 / 100.); }
            }
        }
        flush();
    }
    whisper_free(ctx);
    std::cout << "{\"text\":" << json(text) << ",\"words\":[";
    for (size_t i = 0; i < words.size(); ++i) {
        if (i) std::cout << ',';
        std::cout << "{\"text\":" << json(words[i].text) << ",\"start\":" << words[i].start << ",\"end\":" << words[i].end << '}';
    }
    std::cout << "]}\n";
}
