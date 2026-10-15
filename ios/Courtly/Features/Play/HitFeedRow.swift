import SwiftUI

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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        detail("calendar", "\(HitFormatting.dayAndDate.string(from: hit.startsAt)) · \(HitFormatting.clock.string(from: hit.startsAt)) · \(hit.durationMin) min")
                        detail("mappin.and.ellipse", [hit.court.name, hit.court.address].compactMap { $0 }.joined(separator: ", "))
                        detail("person.2", playersLine)
                    }
                    if hit.players.count > 0 {
                        AvatarStack(cards: hit.everyone, size: 28)
                    }
                    if hit.hasPendingRequest {
                        ActionButton(title: "Requested", style: .grouped, isEnabled: false) {}
                    } else {
                        ActionButton(title: "Request to join", isLoading: isJoining) { join() }
                    }
                    Button("See hit") { navigate(.hit(hit.id)) }
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
    }

    private var playersLine: String {
        let inCount = 1 + hit.players.count
        let who = inCount == 1 ? "Just \(hit.host.firstName) so far" : "\(inCount) in"
        return "\(who) · \(hit.spotsLabel) open"
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CourtlyColor.secondary)
                .frame(width: 18)
            Text(text)
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.ink)
        }
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
