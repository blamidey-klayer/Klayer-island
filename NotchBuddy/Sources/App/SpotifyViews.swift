import SwiftUI
import AppKit

// MARK: - Spotify Card (the home's card when Spotify has the focus)

struct SpotifyCardView: View {
    @ObservedObject private var controller = SpotifyController.shared

    private let green = Color(hex: SpotifyController.green)

    var body: some View {
        Group {
            if controller.automationDenied {
                deniedView
            } else if let track = controller.track {
                nowPlaying(track)
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        // Spotify doesn't announce seeks made in its own window: re-read when the card shows
        .onAppear { controller.refresh() }
    }

    // MARK: Now playing

    // The card is 98 pt tall: artwork row, progress row, controls row.
    private func nowPlaying(_ track: SpotifyTrack) -> some View {
        let subtitle = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                SpotifyArtwork(image: controller.artwork, accent: green)
                    .frame(width: 36, height: 36)
                    .onTapGesture { controller.openSpotify() }
                    .help(track.album.isEmpty ? String(localized: "Open Spotify") : String(localized: "\(track.album) — open Spotify"))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(green).frame(width: 6, height: 6)
                        Text(track.isAd ? String(localized: "Advertisement") : track.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 24)   // the ↗ button sits top-right
            .padding(.top, 6)

            // Position runs on its own clock only while playing and on screen
            TimelineView(.animation(minimumInterval: 0.5, paused: !controller.isPlaying)) { context in
                SpotifyProgress(
                    position: controller.position(at: context.date),
                    duration: track.duration,
                    accent: green,
                    canSeek: !track.isAd && track.duration > 0,
                    onSeek: { controller.seek(to: $0) }
                )
            }
            .padding(.top, 7)

            controls
                .padding(.top, 4)
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                SpotifyIconButton(icon: "shuffle", size: 10,
                                  tint: controller.shuffling ? green : Color(hex: "#6B7079"),
                                  help: controller.shuffling ? "Shuffle on" : "Shuffle off") {
                    controller.setShuffling(!controller.shuffling)
                }
                SpotifyIconButton(icon: "backward.fill", size: 11, tint: Color(hex: "#C5C8CD"), help: "Previous") {
                    controller.previousTrack()
                }
                Button(action: { controller.playPause() }) {
                    ZStack {
                        Circle().fill(Color(hex: "#F5F6F8"))
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(hex: "#0E0F11"))
                            .offset(x: controller.isPlaying ? 0 : 1)
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(SpotifyPressStyle())
                .help(controller.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                SpotifyIconButton(icon: "forward.fill", size: 11, tint: Color(hex: "#C5C8CD"), help: "Next") {
                    controller.nextTrack()
                }
                SpotifyIconButton(icon: "repeat", size: 10,
                                  tint: controller.repeating ? green : Color(hex: "#6B7079"),
                                  help: controller.repeating ? "Repeat on" : "Repeat off") {
                    controller.setRepeating(!controller.repeating)
                }
            }
            Spacer(minLength: 8)
            SpotifyVolume(volume: controller.volume, accent: green) { controller.setVolume($0) }
        }
    }

    // MARK: Idle / not installed / denied (same layout as the other idle cards)

    private var idleView: some View {
        let installed = controller.isInstalled
        return VStack(alignment: .leading, spacing: 6) {
            header(dot: green)
            HStack(spacing: 5) {
                Circle()
                    .fill(installed ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
                    .frame(width: 5, height: 5)
                Text(installed ? String(localized: "Not playing") : String(localized: "Spotify not installed"))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
            .padding(.leading, 108)
            .padding(.top, 2)

            Button(installed ? String(localized: "Open Spotify") : String(localized: "Get Spotify")) {
                installed ? controller.openSpotify() : controller.openDownloadPage()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(green.opacity(0.85))
            .buttonStyle(.plain)
            .padding(.leading, 108)
            .padding(.top, 2)
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(dot: Color(hex: "#F4505E"))
            Text("Allow Klayer Island to control Spotify")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .padding(.leading, 108)
                .padding(.trailing, 12)
            Button("Open Settings…") { controller.openAutomationSettings() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(green.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.leading, 108)
                .padding(.top, 2)
        }
    }

    private func header(dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text("Spotify")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            Text(PillCatalog.definition(for: SpotifyController.pillId)?.subtitle ?? "Integration")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
            Spacer(minLength: 2)
        }
        .padding(.top, 6)
        .padding(.leading, 108)
        .padding(.trailing, 36)
    }
}

// MARK: - Player pieces of the Spotify card

struct SpotifyArtwork: View {
    let image: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accent.opacity(0.7))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.25), value: image)
        .contentShape(Rectangle())
    }
}

/// Thin bar with elapsed / remaining time; drag or click anywhere on it to seek.
struct SpotifyProgress: View {
    let position: Double
    let duration: Double
    let accent: Color
    let canSeek: Bool
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.format(fraction * duration))
                .frame(minWidth: 26, alignment: .trailing)
            SpotifyBar(fraction: fraction, accent: accent, enabled: canSeek,
                       onChange: { dragFraction = $0 },
                       onCommit: { f in
                           onSeek(f * duration)
                           dragFraction = nil
                       })
                .frame(height: 10)
            Text(duration > 0 ? "-" + Self.format(max(0, duration - fraction * duration)) : "")
                .frame(minWidth: 28, alignment: .leading)
        }
        .font(.system(size: 9.5).monospacedDigit())
        .foregroundColor(Color(hex: "#6B7079"))
    }

    static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct SpotifyVolume: View {
    let volume: Int
    let accent: Color
    let onChange: (Int) -> Void

    private var icon: String {
        switch volume {
        case 0:       return "speaker.slash.fill"
        case 1..<34:  return "speaker.wave.1.fill"
        case 34..<67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#6B7079"))
                .frame(width: 13, alignment: .trailing)
            SpotifyBar(fraction: Double(volume) / 100, accent: accent, enabled: true,
                       onChange: { onChange(Int(($0 * 100).rounded())) },
                       onCommit: { onChange(Int(($0 * 100).rounded())) })
                .frame(width: 44, height: 10)
        }
        .help(String(localized: "Volume \(volume)%"))
    }
}

/// Player slider: grey track, filled part turns green and grows a knob on hover.
struct SpotifyBar: View {
    let fraction: Double
    let accent: Color
    let enabled: Bool
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let f = min(1, max(0, fraction))
            let active = enabled && (hovering || dragging)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: active ? 4 : 3)
                Capsule()
                    .fill(active ? accent : Color(hex: "#C5C8CD"))
                    .frame(width: w * f, height: active ? 4 : 3)
                if active {
                    Circle()
                        .fill(Color(hex: "#F5F6F8"))
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: min(w - 9, max(0, w * f - 4.5)))
                }
            }
            .frame(width: w, height: geo.size.height)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        dragging = true
                        onChange(min(1, max(0, g.location.x / w)))
                    }
                    .onEnded { g in
                        guard enabled else { return }
                        dragging = false
                        onCommit(min(1, max(0, g.location.x / w)))
                    }
            )
        }
    }
}

struct SpotifyIconButton: View {
    let icon: String
    let size: CGFloat
    let tint: Color
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(hovered ? tint.opacity(1).lighter(by: 0.2) : tint)
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(SpotifyPressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .help(help)
    }
}

struct SpotifyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
