import Foundation

// MARK: - Test harness

@main
enum ChatParsingTests {

    static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got.debugDescription)")
            print("    expected: \(expected.debugDescription)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") }
        else      { print("  ✗ \(label)"); failures += 1 }
    }

    // MARK: - Entry point

    static func main() {

        print("ChatMarkdown.parse")
        let blocks = ChatMarkdown.parse(
            "## Hello\n\nThis is a paragraph.\n\n- item 1\n- item 2\n\n```swift\nlet x = 1\n```")
        checkTrue("heading count",    blocks.filter { if case .heading   = $0 { return true }; return false }.count == 1)
        checkTrue("paragraph count",  blocks.filter { if case .paragraph = $0 { return true }; return false }.count == 1)
        checkTrue("list item count",  blocks.filter { if case .listItem  = $0 { return true }; return false }.count == 2)
        checkTrue("code block count", blocks.filter { if case .codeBlock = $0 { return true }; return false }.count == 1)
        if case .heading(let level, let text) =
            blocks.first(where: { if case .heading = $0 { return true }; return false })! {
            checkTrue("heading level 2", level == 2)
            checkTrue("heading text",    text == "Hello")
        } else { print("  ✗ heading not found"); failures += 1 }

        print("ChatMarkdown.parse — extended")
        // Numbered list preserves number
        let numBlocks = ChatMarkdown.parse("1. first\n2. second")
        let numItems = numBlocks.filter { if case .listItem = $0 { return true }; return false }
        checkTrue("ordered list count", numItems.count == 2)
        if case .listItem(let prefix, _, _) = numItems.first! {
            checkTrue("ordered prefix is '1.'", prefix == "1.")
        }
        // Heading requires space after #
        checkTrue("heading with space", ChatMarkdown.parse("## Hi").contains { if case .heading = $0 { return true }; return false })
        checkTrue("#nospace is paragraph", ChatMarkdown.parse("#nospace").contains { if case .paragraph = $0 { return true }; return false })
        // Nested list indent
        let nested = ChatMarkdown.parse("- top\n  - nested")
        let items = nested.filter { if case .listItem = $0 { return true }; return false }
        checkTrue("nested list count", items.count == 2)
        if case .listItem(_, _, let indent) = items[1] { checkTrue("nested indent = 1", indent == 1) }
        // Blockquote
        let qBlocks = ChatMarkdown.parse("> quoted text")
        checkTrue("blockquote parsed", qBlocks.contains { if case .quote = $0 { return true }; return false })
        if case .quote(let text) = qBlocks.first! { checkTrue("quote text", text == "quoted text") }
        // Paragraph stops before ordered list
        let mixBlocks = ChatMarkdown.parse("intro\n1. item")
        checkTrue("paragraph + ordered list", mixBlocks.filter { if case .paragraph = $0 { return true }; return false }.count == 1
                  && mixBlocks.filter { if case .listItem = $0 { return true }; return false }.count == 1)

        finish()
    }

    // MARK: - Finish

    private static func finish() -> Never {
        // ── ChatMarkdown.toOneLine ──────────────────────────────────────────────
        print("ChatMarkdown.toOneLine")
        do {
            // multi-line joined with space
            checkTrue("multi-line joined",
                ChatMarkdown.toOneLine("line one\nline two\nline three") == "line one line two line three")

            // bold stripped
            checkTrue("bold stripped",
                ChatMarkdown.toOneLine("**hello** world") == "hello world")

            // heading stripped
            checkTrue("heading stripped",
                ChatMarkdown.toOneLine("## My Title\nsome text") == "My Title some text")

            // empty input → empty
            checkTrue("empty → empty", ChatMarkdown.toOneLine("").isEmpty)

            // truncation
            let long = ChatMarkdown.toOneLine(String(repeating: "x ", count: 200), maxChars: 10)
            checkTrue("truncated to maxChars", long.count <= 10)

            // stop at blank line
            checkTrue("blank line → first para only",
                ChatMarkdown.toOneLine("First para.\n\nSecond para.") == "First para.")

            // stop at --- separator
            checkTrue("--- separator → first para only",
                ChatMarkdown.toOneLine("Done. Single commit 450a657 on github-pulse.\n\n---\n\nFiles touched (7)…")
                    == "Done. Single commit 450a657 on github-pulse.")

            // stop at *** separator
            checkTrue("*** separator → first para only",
                ChatMarkdown.toOneLine("Summary line.\n***\nMore details.") == "Summary line.")

            // stop at table row (|)
            checkTrue("table row → first para only",
                ChatMarkdown.toOneLine("Result:\n| Col1 | Col2 |\n|---|---|\n| A | B |") == "Result:")

            // strip leading bullet -
            checkTrue("strip bullet -",
                ChatMarkdown.toOneLine("- item one\n- item two") == "item one item two")

            // strip leading bullet *
            checkTrue("strip bullet *",
                ChatMarkdown.toOneLine("* first\n* second") == "first second")

            // strip ordered list
            checkTrue("strip ordered list",
                ChatMarkdown.toOneLine("1. step one\n2. step two") == "step one step two")

            // first paragraph empty → fall through to next
            checkTrue("empty first para → next",
                ChatMarkdown.toOneLine("\n\nActual content.") == "Actual content.")
        }

        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        } else {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
    }
}
