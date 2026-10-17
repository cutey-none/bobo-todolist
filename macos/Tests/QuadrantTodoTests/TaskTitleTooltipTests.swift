import XCTest
@testable import QuadrantTodo

final class TaskTitleTooltipTests: XCTestCase {
    func testOnlyTruncatedTitlesNeedTooltip() {
        XCTAssertFalse(TaskTitleTooltip.isTruncated(fullWidth: 80, shownWidth: 80))
        XCTAssertFalse(TaskTitleTooltip.isTruncated(fullWidth: 80.3, shownWidth: 80), "Sub-point rounding is not truncation")
        XCTAssertTrue(TaskTitleTooltip.isTruncated(fullWidth: 260, shownWidth: 180))
    }

    func testBubbleHugsShortTextAndCapsLongText() {
        XCTAssertEqual(TaskTitleTooltip.bubbleWidth(textWidth: 120.4, containerWidth: 680), 142)
        XCTAssertEqual(TaskTitleTooltip.bubbleWidth(textWidth: 900, containerWidth: 680), 440)
        XCTAssertEqual(TaskTitleTooltip.bubbleWidth(textWidth: 900, containerWidth: 400), 352)
    }
}
