import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - The dropped file, as the quick chat sends it (Task 14)
//
// The chat has no tool: the file the user dropped goes inside the message itself. An image as
// base64, a PDF as its text, a text file as it is. Foundation only (PDFKit when the platform
// has it), so the rules are tested on any machine by scripts/test-claude-cli.sh.

/// An image block of a chat message.
struct ChatImage: Equatable, Sendable {
    let mediaType: String
    let base64: String
}

/// What a dropped file adds to the message that carries it: a text (its name, and its content
/// for a PDF or a text file) and, for an image, the image itself.
struct ChatAttachment: Equatable, Sendable {
    let name: String
    let text: String
    let image: ChatImage?

    /// The file is attached, or refused with a French message shown to the user (Claude is
    /// not started for it).
    enum Outcome: Equatable, Sendable {
        case ready(ChatAttachment)
        case refused(String)
    }

    /// 5 MB per image: under the 10 MB of base64 the API takes for one image.
    static let maxImageBytes = 5 * 1024 * 1024
    /// A PDF's text is cut after 200 000 characters.
    static let maxPDFCharacters = 200_000
    /// A text file goes inline up to 200 KB.
    static let maxTextBytes = 200_000

    static let unsupportedMessage = "Ce type de fichier n'est pas pris en charge."
    static let unreadableMessage = "Impossible de lire ce fichier."
    static let imageTooLargeMessage = "Cette image dépasse 5 Mo."
    static let textTooLargeMessage = "Ce fichier dépasse 200 Ko."
    static let pdfWithoutTextMessage = "Ce PDF ne contient pas de texte lisible."

    /// The attachment of a file of `kind`. `data` is the file's bytes (nil when it could not
    /// be read), `pdfText` the text PDFKit found in a PDF (nil when it found none).
    static func make(name: String, kind: ChatAttachmentKind, data: Data?, pdfText: String?) -> Outcome {
        let header = "Fichier : \(name)"
        switch kind {
        case .unsupported:
            return .refused(unsupportedMessage)

        case .image(let mediaType):
            guard let data else { return .refused(unreadableMessage) }
            guard data.count <= maxImageBytes else { return .refused(imageTooLargeMessage) }
            return .ready(ChatAttachment(name: name, text: header,
                                         image: ChatImage(mediaType: mediaType, base64: data.base64EncodedString())))

        case .pdf:
            guard let pdfText, !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .refused(pdfWithoutTextMessage)
            }
            var body = String(pdfText.prefix(maxPDFCharacters))
            if pdfText.count > maxPDFCharacters {
                body += "\n\n[Texte coupé à 200 000 caractères.]"
            }
            return .ready(ChatAttachment(name: name, text: "\(header)\n\n\(body)", image: nil))

        case .text:
            guard let data else { return .refused(unreadableMessage) }
            guard data.count <= maxTextBytes else { return .refused(textTooLargeMessage) }
            guard let content = String(data: data, encoding: .utf8) else { return .refused(unreadableMessage) }
            return .ready(ChatAttachment(name: name, text: "\(header)\n\n\(content)", image: nil))
        }
    }

    /// Reads the dropped file at `url` and builds its attachment. The size on disk is checked
    /// before anything is read, so a huge file is refused without loading it. Blocking (a PDF
    /// can take a moment): call it off the main thread.
    static func load(url: URL) -> Outcome {
        let name = url.lastPathComponent
        let kind = ChatAttachmentKind.forExtension(url.pathExtension)
        if kind == .unsupported { return .refused(unsupportedMessage) }

        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
            return .refused(unreadableMessage)
        }
        switch kind {
        case .image where size.intValue > maxImageBytes:
            return .refused(imageTooLargeMessage)
        case .text where size.intValue > maxTextBytes:
            return .refused(textTooLargeMessage)
        case .pdf:
            return make(name: name, kind: kind, data: nil, pdfText: pdfText(at: url))
        default:
            break
        }
        return make(name: name, kind: kind, data: try? Data(contentsOf: url), pdfText: nil)
    }

    /// The text of the PDF at `url`, nil when PDFKit cannot open it or this platform has no
    /// PDFKit (the Linux tests).
    private static func pdfText(at url: URL) -> String? {
        #if canImport(PDFKit)
        return PDFDocument(url: url)?.string
        #else
        return nil
        #endif
    }
}

// MARK: - One message of the chat

/// What one message of the chat carries to Claude Code: a single text and the images, written
/// on the process's stdin as one `stream-json` line (images first).
struct ChatOutgoing: Equatable {
    let text: String
    let images: [ChatImage]

    /// The line written on stdin.
    var line: String {
        ClaudeStream.userLine(text: text, images: images.map { (mediaType: $0.mediaType, base64: $0.base64) })
    }

    /// The window the user attached to the chat, said in plain text.
    static func windowContext(appName: String, title: String, url: String?) -> String {
        var text = "Contexte : fenêtre « \(title) » de l'app \(appName)"
        if let url { text += ", URL \(url)" }
        return text
    }

    /// How much of the earlier exchanges goes back to a new process, in characters.
    static let transcriptLimit = 20_000

    /// The earlier exchanges of a conversation, for the first message of a new process (the
    /// previous one stopped after 10 minutes without a message, or died): without them the
    /// new process would answer a follow-up with no memory of the conversation. The newest
    /// exchanges are kept up to `limit` characters, in their order. Nil when there is none.
    static func transcript(_ messages: [(fromUser: Bool, text: String)], limit: Int = transcriptLimit) -> String? {
        var kept: [String] = []
        var used = 0
        for message in messages.reversed() {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            var line = (message.fromUser ? "Utilisateur : " : "Klay : ") + text
            if kept.isEmpty, line.count > limit {
                // The newest message alone is too long: its end is what the next question follows.
                line = "…" + String(line.suffix(limit - 1))
            }
            guard used + line.count <= limit else { break }
            kept.append(line)
            used += line.count + 1
        }
        guard !kept.isEmpty else { return nil }
        return (["Échanges précédents de cette conversation :"] + kept.reversed()).joined(separator: "\n")
    }

    /// The message: the earlier exchanges when a new process starts, the window context, the
    /// dropped file, then the question. Each part only when it is there.
    static func compose(query: String, windowContext: String?, attachment: ChatAttachment?,
                        transcript: String?) -> ChatOutgoing {
        let parts = [transcript, windowContext, attachment?.text, query].compactMap { $0 }
        return ChatOutgoing(text: parts.joined(separator: "\n\n"),
                            images: attachment?.image.map { [$0] } ?? [])
    }
}
