import Foundation

/// The Granola shortcut of the compact island (spec §5): one link, opened through an injected
/// opener so the test never launches an app.
@main
enum GranolaLinkTests {
    static func main() {
        // The deep link that creates a note.
        precondition(GranolaLink.newNote.absoluteString == "granola://new-document")
        print("  ok  new_note_is_the_granola_new_document_link")

        // open(using:) calls the opener once with that link and returns its answer.
        for answer in [true, false] {
            var received: [URL] = []
            let result = GranolaLink.open(using: { url in
                received.append(url)
                return answer
            })
            precondition(received == [GranolaLink.newNote])
            precondition(result == answer)
        }
        print("  ok  open_calls_the_opener_once_and_returns_its_answer")

        print("Granola link: 2 cases passed")
    }
}
