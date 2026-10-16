import XCTest
@testable import QuadrantTodo

final class ReleaseInfoTests: XCTestCase {
    private func release(tag: String, body: String? = "修复若干问题", assets: [String]) throws -> ReleaseInfo {
        let assetJSON = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"#
        }.joined(separator: ",")
        let bodyJSON = body.map { #""\#($0)""# } ?? "null"
        let json = #"{"tag_name":"\#(tag)","body":\#(bodyJSON),"assets":[\#(assetJSON)]}"#
        return try ReleaseInfo.decode(Data(json.utf8))
    }

    func testNewerReleaseWithMatchingAssetsIsAvailable() throws {
        let info = try release(tag: "v0.0.2", assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        let lookup = info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64")
        let expected = UpdatePackage(
            version: AppVersion("0.0.2")!,
            dmgName: "QuadrantTodo_0.0.2_arm64.dmg",
            dmgURL: URL(string: "https://example.com/QuadrantTodo_0.0.2_arm64.dmg")!,
            checksumURL: URL(string: "https://example.com/QuadrantTodo_0.0.2_arm64.dmg.sha256")!
        )
        XCTAssertEqual(lookup, .available(expected, notes: "修复若干问题"))
    }

    func testSameOrOlderReleaseIsUpToDate() throws {
        let info = try release(tag: "v0.0.1", assets: [])
        XCTAssertEqual(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .upToDate(AppVersion("0.0.1")!))
        XCTAssertEqual(info.lookup(current: AppVersion("0.1.0")!, architecture: "arm64"), .upToDate(AppVersion("0.0.1")!))
    }

    func testMissingArchitectureOrChecksumIsReported() throws {
        let armOnly = try release(tag: "v0.0.2", assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        XCTAssertEqual(armOnly.lookup(current: AppVersion("0.0.1")!, architecture: "x86_64"), .missingPackage(AppVersion("0.0.2")!))

        let noChecksum = try release(tag: "v0.0.2", assets: ["QuadrantTodo_0.0.2_arm64.dmg"])
        XCTAssertEqual(noChecksum.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .missingPackage(AppVersion("0.0.2")!))
    }

    func testAssetNamesMustMatchExactly() throws {
        let info = try release(tag: "v0.0.2", assets: [
            "quadranttodo_0.0.2_arm64.dmg", "quadranttodo_0.0.2_arm64.dmg.sha256",
            "QuadrantTodo_0.0.1_arm64.dmg", "QuadrantTodo_0.0.1_arm64.dmg.sha256"
        ])
        XCTAssertEqual(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .missingPackage(AppVersion("0.0.2")!))
    }

    func testUnparseableTagYieldsNoLookup() throws {
        let info = try release(tag: "v0.0.2-beta", assets: [
            "QuadrantTodo_0.0.2-beta_arm64.dmg", "QuadrantTodo_0.0.2-beta_arm64.dmg.sha256"
        ])
        XCTAssertNil(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"))
    }

    func testNullBodyBecomesEmptyNotes() throws {
        let info = try release(tag: "v0.0.2", body: nil, assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        guard case .available(_, let notes) = info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64") else {
            return XCTFail("应为 available")
        }
        XCTAssertEqual(notes, "")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ReleaseInfo.decode(Data("not json".utf8)))
    }

    func testCurrentArchitectureIsKnown() {
        XCTAssertTrue(["arm64", "x86_64"].contains(CPUArchitecture.current))
    }
}
