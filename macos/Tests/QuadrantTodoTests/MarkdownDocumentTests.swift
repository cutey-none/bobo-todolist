import XCTest
@testable import QuadrantTodo

final class MarkdownDocumentTests: XCTestCase {
    func testTaskListMarkersRenderWithoutBecomingTaskModels() {
        let markdown = "- [ ] 未完成\n* [x] 已完成\n+ [X] **强调**\n- 普通列表\n- [ ]\n- [x]不是任务标记"
        XCTAssertEqual(MarkdownDocument.parse(markdown), [
            .task(checked: false, text: "未完成"),
            .task(checked: true, text: "已完成"),
            .task(checked: true, text: "**强调**"),
            .bullet("普通列表"),
            .task(checked: false, text: ""),
            .bullet("[x]不是任务标记")
        ])
        XCTAssertEqual(MarkdownDocument.plainText("- [ ] 未完成\n- [x] 已完成"), "未完成\n已完成")
        XCTAssertEqual(MarkdownDocument.parse("```\n- [ ] 代码\n```"), [.code("- [ ] 代码")])
    }

    func testParsesDescriptionBlocks() {
        let markdown = """
        ### 关键信息
        第一行正文
        第二行正文

        - 普通列表
        * 另一种列表
        1. 有序列表
        > 引用内容
        ![截图](attachments/a.png)
        ```
        let x = 1
        ```
        """

        XCTAssertEqual(MarkdownDocument.parse(markdown), [
            .heading(level: 3, text: "关键信息"),
            .paragraph("第一行正文\n第二行正文"),
            .bullet("普通列表"),
            .bullet("另一种列表"),
            .ordered(number: 1, text: "有序列表"),
            .quote("引用内容"),
            .image(alt: "截图", source: "attachments/a.png"),
            .code("let x = 1")
        ])
    }

    func testHashWithoutSpaceIsParagraph() {
        XCTAssertEqual(MarkdownDocument.parse("#标签"), [.paragraph("#标签")])
    }

    func testPlainTextDropsMarkupAndImages() {
        let markdown = "## 标题\n- 列表\n![图](attachments/a.png)"
        XCTAssertEqual(MarkdownDocument.plainText(markdown), "标题\n列表")
        XCTAssertEqual(MarkdownDocument.imageSources(in: markdown), ["attachments/a.png"])
    }
}
