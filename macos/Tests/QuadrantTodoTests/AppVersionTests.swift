import XCTest
@testable import QuadrantTodo

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndPrefixedVersions() {
        XCTAssertEqual(AppVersion("0.0.1")?.components, [0, 0, 1])
        XCTAssertEqual(AppVersion("v0.1.0")?.components, [0, 1, 0])
        XCTAssertEqual(AppVersion(" V1.2 ")?.components, [1, 2])
    }

    func testRejectsNonNumericVersions() {
        XCTAssertNil(AppVersion("v0.0.2-beta"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
        XCTAssertNil(AppVersion("１.0")) // 全角数字
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertLessThan(AppVersion("0.0.9")!, AppVersion("0.0.10")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0.0")!)
        XCTAssertGreaterThan(AppVersion("0.1")!, AppVersion("0.0.9")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("1.0")! < AppVersion("1.0.0")!)
        XCTAssertLessThan(AppVersion("1.0")!, AppVersion("1.0.1")!)
    }

    func testDescriptionDropsPrefix() {
        XCTAssertEqual(AppVersion("v0.0.2")?.description, "0.0.2")
    }
}
