import XCTest
@testable import QuadrantTodo

final class UpdateChecksumTests: XCTestCase {
    private let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let dmgName = "QuadrantTodo_0.0.2_arm64.dmg"

    func testParsesShasumOutputVariants() {
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(abcHash)  \(dmgName)\n", fileName: dmgName), abcHash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(abcHash.uppercased())  \(dmgName)", fileName: dmgName), abcHash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(abcHash) *\(dmgName)", fileName: dmgName), abcHash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(abcHash)\n", fileName: dmgName), abcHash)
    }

    func testRejectsWrongNameOrMalformedHash() {
        XCTAssertNil(UpdateChecksum.expectedHash(in: "\(abcHash)  Other.dmg", fileName: dmgName))
        XCTAssertNil(UpdateChecksum.expectedHash(in: "abc123  \(dmgName)", fileName: dmgName))
        XCTAssertNil(UpdateChecksum.expectedHash(in: "", fileName: dmgName))
        XCTAssertNil(UpdateChecksum.expectedHash(in: String(repeating: "z", count: 64), fileName: dmgName))
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try UpdateChecksum.sha256Hex(of: url), abcHash)
    }

    func testResultIsConsumedOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("result-\(UUID().uuidString).json")
        try Data(#"{"status":"success","version":"0.0.2","backup":"/tmp/b 中文"}"#.utf8).write(to: url)

        let result = UpdateResult.consume(at: url)
        XCTAssertEqual(result, UpdateResult(status: "success", version: "0.0.2", backup: "/tmp/b 中文"))
        XCTAssertEqual(result?.succeeded, true)
        XCTAssertEqual(result?.title, "已升级到 0.0.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(UpdateResult.consume(at: url))
    }

    func testCorruptResultIsDiscarded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("result-\(UUID().uuidString).json")
        try Data("garbage".utf8).write(to: url)
        XCTAssertNil(UpdateResult.consume(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailureResultsExplainThatDataIsUntouched() {
        XCTAssertFalse(UpdateResult(status: "restored", version: "0.0.2", backup: "/b").succeeded)
        XCTAssertTrue(UpdateResult(status: "restored", version: "0.0.2", backup: "/b").detail.contains("/b"))
        XCTAssertEqual(UpdateResult(status: "timeout", version: "0.0.2", backup: "/b").title, "升级未完成")
    }
}
