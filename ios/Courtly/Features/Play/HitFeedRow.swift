import SwiftUI
import UIKit

/// One open hit. Tap to open it up: where, how long, who's in, and the button to ask.
struct HitFeedRow: View {
    let hit: Hit
    let isExpanded: Bool
    let onTap: () -> Void

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    PlayerAvatar(card: hit.host, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.feedTitle)
                            .font(CourtlyFont.bodySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                            .lineLimit(1)
                        Text(hit.feedSubtitle)
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CourtlyColor.placeholder)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(HitFormatting.dayAndDate.string(from: hit.startsAt)) · \(HitFormatting.clock.string(from: hit.startsAt)) · \(hit.durationMin) min")
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.ink)
                        Button(action: openInMaps) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.court.name)
                                    .font(CourtlyFont.secondary)
                                    .foregroundStyle(CourtlyColor.ink)
                                if let address = hit.court.address {
                                    Text(address)
                                        .font(CourtlyFont.secondary)
                                        .foregroundStyle(CourtlyColor.blue)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(hit.court.name) in Maps")
                        HStack(spacing: 10) {
                            AvatarStack(cards: hit.everyone, size: 26)
                            Text(playersLine)
                                .font(CourtlyFont.secondary)
                                .foregroundStyle(CourtlyColor.secondary)
                        }
                    }
                    if hit.hasPendingRequest {
                        ActionButton(title: "Requested", style: .grouped, isEnabled: false) {}
                    } else {
                        ActionButton(title: "Request to join", isLoading: isJoining) { join() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
    }

    /// "2 in · 1 spot open · Advanced host"
    private var playersLine: String {
        let inCount = 1 + hit.players.count
        return [inCount == 1 ? "\(hit.host.firstName) so far" : "\(inCount) in", "\(hit.spotsLabel) open", hit.host.level.map { "\($0.title) host" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func openInMaps() {
        let name = hit.court.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://maps.apple.com/?ll=\(hit.court.lat),\(hit.court.lng)&q=\(name)") else { return }
        UIApplication.shared.open(url)
    }

    private func join() {
        isJoining = true
        Task { @MainActor in
            do {
                _ = try await hits.requestToJoin(hit.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}
