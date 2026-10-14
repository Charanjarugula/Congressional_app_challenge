import SwiftUI

/// One open hit in From friends or Near you. Tap the row for details; "Join" asks right away.
struct HitFeedRow: View {
    let hit: Hit

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                navigate(.hit(hit.id))
            } label: {
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
                        if let reason = hit.reason {
                            Text(reason)
                                .font(CourtlyFont.caption)
                                .foregroundStyle(CourtlyColor.blue)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: join) {
                ZStack {
                    Text("Join")
                        .font(CourtlyFont.secondarySemibold)
                        .opacity(isJoining ? 0 : 1)
                    if isJoining {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CourtlyColor.blue)
                    }
                }
                .foregroundStyle(CourtlyColor.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(CourtlyColor.blueTint))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isJoining)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
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
