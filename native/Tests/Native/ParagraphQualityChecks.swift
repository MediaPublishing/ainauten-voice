import Foundation
import VoiceWisprCore
@main struct ParagraphQualityChecks {
 static func main() async throws {
  let url = ModelPaths.support.appendingPathComponent("settings.json")
  let before = try Data(contentsOf:url)
  let document = try JSONDecoder().decode(ExportDocument.self,from:before)
  let matcher = DictionaryMatcher(document.dictionary)
  let formatter=LocalFormatter(modelURL:ModelPaths.formatter)
  try await formatter.prepare()
  let cases:[(String,String)]=[("reported-paragraph","Wir starten immer zuerst mit einer Klaren Spezifikation. indem wir mal ein Braindump machen, was uns vorschwebt, und das Ganze dann in eine saubere Form. Bringen und als Goal definieren lassen. Das ist eigentlich der wichtigste Schritt im Ganzen.Dafür haben wir auch einen Skill gebaut, den du unten stehen findest.Danach lassen wir... Den Prozess losraten. Oftmals wird hier dann. Ein paar Stunden lang gebaut. So auch in diesem Fall. Danach kam die erste Feedback-Runde mit Testen. Hier wurden die Abstände im Bauen dann kleiner. Und Danach. Geht es wieder ans Testen. Wenn dann eine erste Version Als Prototyp steht, lassen wir sie von einem anderen Modell Reviewen und Verbesserungen vorschlagen, Was dann oftmals auch wieder zu einer längeren Backfixrunde führt, und dann kommt der Feinschliff mit User interface. Veröffentlichung und so weiter."),
("relative","Wenn dann eine erste Version Als Prototyp steht, lassen wir sie von einem anderen Modell Reviewen und Verbesserungen vorschlagen, Was dann oftmals auch wieder zu einer längeren Backfixrunde führt, und dann kommt der Feinschliff mit User interface. Veröffentlichung und so weiter."),
("questions","Ist die App bereit? Bitte überweise 12,5% nicht vor Freitag."),
("literals","Die Datei Info.plist liegt bei AInauten.de. Bitte öffne https://example.org/a."),
("filler","Ähm bitte nicht. Senden."),
("version","Version 1.2.3 liegt in Cargo.toml, nicht in Info.plist."),
("list","Erstens 12 Euro nicht senden. Zweitens 3 Dokumente prüfen. Drittens morgen warten."),
("mixed","Das ist der neue Workflow. We check the draft before publishing."),
("english-question","Is the draft ready? Please do not send it before Friday."),
("adjective-before-noun","Zum Beispiel, wenn du einen Neuen Mac hast, und dann kurze Spezifikation, dann kannst du Die App einfach direkt installieren lassen."),
("nominalized-verb","Um das System auch Über Nacht auf Am Laufen zu halten. Wobei das natürlich auch zu. Ungewissen. Resultaten führen kann.")]
  var failures=0
  for (id,source) in cases {
   let input=matcher.replace(in:source)
   let start=ProcessInfo.processInfo.systemUptime
   do {
    let output=try await formatter.format(input,style:.cleaned,context:"",vocabulary:matcher.topVocabulary(in:input))
    let sourceWords=input.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { !["äh", "ähm"].contains(String($0)) }.map(String.init)
    let outputWords=output.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { !["äh", "ähm"].contains(String($0)) }.map(String.init)
    var passed=sourceWords==outputWords
    if id=="reported-paragraph" { passed = passed && output.contains("klaren Spezifikation") && output.contains("Form bringen") && output.contains("Ganzen. Dafür") && output.contains(", was dann") && output.contains("User Interface, Veröffentlichung") && output.contains("\n\n") }
    if id=="relative" { passed = passed && output.contains("erste Version als Prototyp steht") && output.contains(", was dann") }
    if id=="questions" { passed = passed && output.contains("bereit?") && output.contains("12,5%") && output.contains("nicht vor Freitag") }
    if id=="literals" { passed = passed && output.contains("Info.plist") && output.contains(input.split(whereSeparator: \.isWhitespace).first { $0.lowercased().hasPrefix("ainauten.de") }!.trimmingCharacters(in:CharacterSet(charactersIn:".,"))) && output.contains("https://example.org/a") }
    if id=="version" { passed = passed && output.contains("1.2.3") && output.contains("Cargo.toml") && output.contains("Info.plist") }
    if id=="english-question" { passed = passed && output.contains("ready?") }
    if id=="adjective-before-noun" { passed = passed && output.contains("einen neuen Mac") && output.contains("du die App") }
    if id=="nominalized-verb" { passed = passed && output.contains("über Nacht auf am Laufen") && output.contains("zu ungewissen Resultaten") }
    if !passed { failures += 1 }
    let row:[String:Any]=["passed":passed,"id":id,"input":input,"output":output,"needsModel":LocalFormatter.needsModel(input,style:.cleaned),"seconds":ProcessInfo.processInfo.systemUptime-start]
    print(String(decoding:try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]),as:UTF8.self));fflush(stdout)
   } catch { failures += 1; print("CASE_ERROR \(id) \(error)");fflush(stdout) }
  }
  assert(try! Data(contentsOf:url)==before)
  await formatter.shutdown()
  print("PARAGRAPH_NATIVE_RESULT cases=\(cases.count) failures=\(failures) settingsUnchanged=true microphone=false actualASR=false cloud=false")
  if failures>0 {exit(1)}
  try await ParagraphPipelineProbe.main()
 }
}

private actor TranscriptFixture: SpeechTranscribing {
 let sections:[String]
 init(_ sections:[String]) { self.sections=sections }
 func prepare() async throws {}
 func transcribe(samples:[Float], sessionID:UUID, index:Int, offset:Double) async throws -> TranscriptSegment {
  let text=sections[index], time=offset+Double(samples.count)/32000
  return .init(sessionID:sessionID,index:index,text:text,words:text.split(separator:" ").map { .init(text:String($0),start:time,end:time) })
 }
}
private actor MeasuredFormatter: TextFormatting {
 let local:LocalFormatter
 init(_ local:LocalFormatter){self.local=local}
 func prepare() async throws {try await local.prepare()}
 func format(_ text:String,style:TextStyle,context:String,vocabulary:[String]) async throws -> String {
  let start=ProcessInfo.processInfo.systemUptime
  let output=try await local.format(text,style:style,context:context,vocabulary:vocabulary)
  print("WINDOW words=\(text.split(whereSeparator:\.isWhitespace).count) seconds=\(ProcessInfo.processInfo.systemUptime-start)");fflush(stdout)
  return output
 }
}
struct ParagraphPipelineProbe {
 static func main() async throws {
  let url=ModelPaths.support.appendingPathComponent("settings.json"), before=try Data(contentsOf:url)
  let document=try JSONDecoder().decode(ExportDocument.self,from:before)
  let sections:[String]=["Wir starten immer zuerst mit einer Klaren Spezifikation. indem wir mal ein Braindump machen, was uns vorschwebt, und das Ganze dann in eine saubere Form. ", "Bringen und als Goal definieren lassen. Das ist eigentlich der wichtigste Schritt im Ganzen.Dafür haben wir auch einen Skill gebaut, den du unten stehen findest.Danach lassen wir... Den Prozess losraten. ", "Oftmals wird hier dann. Ein paar Stunden lang gebaut. So auch in diesem Fall. Danach kam die erste Feedback-Runde mit Testen. Hier wurden die Abstände im Bauen dann kleiner. Und Danach. Geht es wieder ans Testen. ", "Wenn dann eine erste Version Als Prototyp steht, lassen wir sie von einem anderen Modell Reviewen und Verbesserungen vorschlagen, Was dann oftmals auch wieder zu einer längeren Backfixrunde führt, und dann kommt der Feinschliff mit User interface. Veröffentlichung und so weiter."]
  let local=LocalFormatter(modelURL:ModelPaths.formatter), measured=MeasuredFormatter(local)
  let pipeline=ProcessingPipeline(speech:TranscriptFixture(sections),formatter:measured,coreSamples:16000,overlapSamples:0)
  try await pipeline.start(style:.cleaned,dictionary:document.dictionary)
  try await pipeline.append(samples:[Float](repeating:0.1,count:sections.count*16000))
  let result=try await pipeline.finish()
  print(String(decoding:try JSONSerialization.data(withJSONObject:["output":result.text,"original":result.original,"fallback":result.usedFallback],options:[.sortedKeys]),as:UTF8.self));fflush(stdout)
  guard !result.usedFallback, result.text.contains("saubere Form bringen"), result.text.contains("klaren Spezifikation"), !result.text.contains("Ganzen.Dafür"), result.text.contains(", was dann"), result.text.contains("User Interface, Veröffentlichung"), result.text.contains("\n\n") else {throw VoiceError.message("Paragraph quality failed")}
  guard try Data(contentsOf:url)==before else {throw VoiceError.message("Settings changed")}
  // The sampler currently cannot always preserve quotes. The pipeline must
  // reject that output and recover the full source instead of dropping them.
  let quotation = "Er sagte: „Bitte Nicht senden.“ Danach hat er die App geschlossen."
  let quotedPipeline=ProcessingPipeline(speech:TranscriptFixture([quotation]),formatter:local,coreSamples:16000,overlapSamples:0)
  try await quotedPipeline.start(style:.cleaned,dictionary:[])
  try await quotedPipeline.append(samples:[Float](repeating:0.1,count:16000))
  let quoted=try await quotedPipeline.finish()
  guard quoted.text.contains("„"), quoted.text.contains("“"),
        quoted.text.lowercased().split(whereSeparator:{ !$0.isLetter && !$0.isNumber }) == quotation.lowercased().split(whereSeparator:{ !$0.isLetter && !$0.isNumber }),
        try Data(contentsOf:url)==before else {throw VoiceError.message("Quoted statement changed")}
  print("QUOTED_PIPELINE_RESULT cases=1 failures=0 fallback=\(quoted.usedFallback) quotationMarksPreserved=true microphone=false actualASR=false cloud=false")
  await local.shutdown()
  print("PARAGRAPH_PIPELINE_RESULT cases=1 failures=0 fixture=transcript-adapter microphone=false actualASR=false cloud=false")
 }
}
