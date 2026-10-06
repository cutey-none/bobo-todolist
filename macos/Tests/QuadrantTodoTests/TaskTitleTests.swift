import XCTest
@testable import QuadrantTodo

final class TaskTitleTests: XCTestCase {
    func testPastedNewlinesBecomeSpaces() {
        XCTAssertEqual(TaskTitle.singleLine("整理\n材料\r\n周三"), "整理 材料 周三")
    }

    func testValidTitleIsTrimmed() {
        XCTAssertEqual(TaskTitle.validate("  整理材料  "), .success("整理材料"))
    }

    func testBlankTitleIsRejected() {
        XCTAssertEqual(TaskTitle.validate("   "), .failure(.empty))
        XCTAssertEqual(TaskTitle.validate("\n"), .failure(.empty))
    }

    func testTitleLimitCountsCharactersNotBytes() {
        XCTAssertEqual(TaskTitle.validate(String(repeating: "字", count: 200)), .success(String(repeating: "字", count: 200)))
        XCTAssertEqual(TaskTitle.validate(String(repeating: "字", count: 201)), .failure(.tooLong))
    }
}
