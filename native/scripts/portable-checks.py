#!/usr/bin/env python3
"""Run the same contract cases on CLT-only Macs where Apple XCTest is unavailable.
Assertion adaptation is temporary and lives in ignored artifacts; original XCTest
sources remain usable by full Xcode. No tested production behavior is mocked here.
"""
import os, pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
out = root/'artifacts/portable-checks'; out.mkdir(parents=True, exist_ok=True)
mapping = {'XCTestCase':'ContractCase', 'XCTAssertEqual':'expectEqual', 'XCTAssertTrue':'expectTrue', 'XCTAssertFalse':'expectFalse', 'XCTAssertNil':'expectNil', 'XCTAssertGreaterThan':'expectGreater', 'XCTAssertLessThan':'expectLess', 'XCTAssertThrowsError':'expectThrows', 'XCTUnwrap':'unwrap', 'XCTFail':'fail'}
calls = []
for source in sorted((root/'Tests/VoiceWisprCoreTests').glob('*.swift')):
    text = source.read_text().replace('import XCTest', 'import Foundation')
    cls = re.search(r'final class (\w+): XCTestCase', text).group(1)
    for name, modifiers in re.findall(r'func (test\w+)\(\)\s*([^\{]*)\{', text):
        inv = f'{cls}().{name}()'
        if 'async' in modifiers: inv = 'await ' + inv
        if 'throws' in modifiers: inv = 'try ' + inv
        calls.append(f'        await run("{cls}.{name}") {{ {inv} }}')
    for a,b in mapping.items(): text = re.sub(r'\b'+a+r'\b', b, text)
    (out/source.name).write_text(text)
support = '''import Foundation
class ContractCase {}
enum CheckFailure: Error { case unwrapped }
var failures = 0
func fail(_ message: String = "failure", file: StaticString = #filePath, line: UInt = #line) { failures += 1; print("FAIL \\(file):\\(line) \\(message)") }
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if a != b { fail("\\(a) != \\(b) \\(message)", file: file, line: line) } }
func expectEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { if abs(a-b) > accuracy { fail("\\(a) != \\(b)", file:file,line:line) } }
func expectTrue(_ x: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if !x { fail(message, file:file,line:line) } }
func expectFalse(_ x: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { expectTrue(!x,message,file:file,line:line) }
func expectNil<T>(_ x: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(x == nil,file:file,line:line) }
func expectGreater<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { expectTrue(a > b,file:file,line:line) }
func expectLess<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { expectTrue(a < b,file:file,line:line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try expression(); fail("expected error",file:file,line:line) } catch {} }
func unwrap<T>(_ x: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T { guard let x else { fail("nil",file:file,line:line); throw CheckFailure.unwrapped }; return x }
@MainActor func run(_ name: String, _ body: () async throws -> Void) async { let before = failures; do { try await body() } catch { fail("\\(name): \\(error)") }; print("\\(failures == before ? "PASS" : "FAIL") \\(name)") }
@main struct Checks { @MainActor static func main() async {
'''
(out/'Runner.swift').write_text(support+'\n'.join(calls)+f'\n        print("Executed {len(calls)} contract cases; failures: \\(failures)")\n        exit(failures == 0 ? 0 : 1)\n    }}\n}}\n')
# This adapter links the native SwiftPM object layout below. Swift 6.4 defaults
# to swiftbuild, whose product layout differs; select the matching engine.
subprocess.run(['swift','build','--build-system','native','--target','VoiceWisprCore','--jobs','4'], cwd=root, check=True)
build = root/'.build/arm64-apple-macosx/debug'
module = build/'Modules'
cmd = ['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macosx14.0','-I',str(module),'-I',str(root/'Sources/CSQLite'),'-I',str(build/'FastClusterWrapper.build'),'-I',str(build/'MachTaskSelfWrapper.build'),'-F',str(build),'-L',str(build),'-framework','llama','-framework','Accelerate','-framework','CoreML','-framework','AppKit','-framework','AVFoundation','-framework','ApplicationServices','-framework','Security','-framework','Carbon','-lsqlite3','-lc++','-Xlinker','-rpath','-Xlinker',str(build)]
for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
    cmd += ['-Xcc', '-fmodule-map-file=' + str(root/'.build/checkouts/FluidAudio/Sources'/target/'include/module.modulemap')]
    cmd += ['-Xcc', '-I'+str(root/'.build/checkouts/FluidAudio/Sources'/target/'include')]
objects=[]
for target in ['VoiceWisprCore.build','FluidAudio.build','FastClusterWrapper.build','MachTaskSelfWrapper.build']:
    objects += [str(p) for p in (build/target).glob('*.o')]
cmd += objects + [str(p) for p in out.glob('*.swift')] + ['-o',str(out/'VoiceWisprChecks')]
result = subprocess.run(cmd,cwd=root)
if result.returncode: raise SystemExit(result.returncode)
subprocess.run([str(out/'VoiceWisprChecks')],cwd=root,check=True,env={**os.environ, 'VOICE_TEST_PYTHON': sys.executable})
