// CI-only prerequisite: existing German fast-path tests require Apple's lexical assets.
// These assets are loaded on the disposable runner, never on the owner's Mac.
import Foundation
import NaturalLanguage

final class AssetRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var available = false
    private var message = ""
    func finish(_ result: NLTagger.AssetsResult, _ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        completed = true
        available = result == .available
        message = error?.localizedDescription ?? String(describing: result)
    }
    func snapshot() -> (Bool, Bool, String) {
        lock.lock(); defer { lock.unlock() }
        return (completed, available, message)
    }
}

let request = AssetRequest()
print("German schemes before request:", NLTagger.availableTagSchemes(for: .word, language: .german))
NLTagger.requestAssets(for: .german, tagScheme: .lexicalClass) { result, error in
    request.finish(result, error)
}
let deadline = Date().addingTimeInterval(180)
while !request.snapshot().0, Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
let (completed, available, message) = request.snapshot()
guard completed, available else {
    fputs("German lexical assets unavailable: \(message)\n", stderr)
    exit(1)
}
let sample = "Dies ist ein kurzer Test der Spracherkennung."
let tagger = NLTagger(tagSchemes: [.lexicalClass])
tagger.string = sample
tagger.setLanguage(.german, range: sample.startIndex..<sample.endIndex)
let tags = tagger.tags(in: sample.startIndex..<sample.endIndex, unit: .word,
                       scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation])
print("German lexical tags:", tags.map { "\(sample[$0.1]):\($0.0?.rawValue ?? "nil")" })
guard let test = sample.range(of: "Test"),
      tagger.tag(at: test.lowerBound, unit: .word, scheme: .lexicalClass).0 == .noun else {
    fputs("German noun classification is not ready; do not skip its tests.\n", stderr)
    exit(1)
}
print("German lexical assets ready.")
