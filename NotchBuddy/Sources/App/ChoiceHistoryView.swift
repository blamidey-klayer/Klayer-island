import SwiftUI

// MARK: - Last choices (home of the open island)

/// The last permissions and questions answered from the island, under the conversations on the
/// home of the open island (spec §6): 5 rows at most, newest first, in grey at 55 % opacity so
/// they stay behind the running sessions. A row reads "HH:mm · session · prompt · answer" on one
/// line, the prompt cut at its end when too long. The history stays on the Mac (`ChoiceHistory`).
struct ChoiceHistoryView: View {
    /// `AppState.recentChoices`, newest first.
    let choices: [ChoiceRecord]

    /// Rows shown at most.
    static let limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(choices.prefix(Self.limit).enumerated()), id: \.offset) { _, choice in
                ChoiceHistoryRow(row: choice.row())
            }
        }
        .foregroundColor(Color(hex: "#9398A1"))
        .opacity(0.55)
    }
}

private struct ChoiceHistoryRow: View {
    let row: ChoiceRecord.Row

    var body: some View {
        // The answer is short (`Row.answerLimit`) and always whole: the summary gives way.
        HStack(spacing: 4) {
            Text(row.summary)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("· " + row.answer)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 12)
    }
}
