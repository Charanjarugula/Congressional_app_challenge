import SwiftUI

/// A request to answer, an invite to claim, or an accepted ask that opens the chat.
struct NeedsReplyCard: View {
    let item: NeedsReplyItem

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var working: String?
    @State private var errorMessage: String?

    var body: some View {
        Card(padding: 16, radius: 22) {
            switch item.kind {
            case .joinRequest: joinRequest
            case .invite: invite
            case .accepted: accepted
            }
        }
        .errorAlert($errorMessage)
    }

    // MARK: - Variants

    private var joinRequest: some View {
        VStack(spacing: 12) {
            Button {
                if let requestID = item.requestId { navigate(.request(requestID)) }
            } label: {
                personRow(
                    title: "\(item.person.displayName) asked to join",
                    subtitle: "\(item.hit.shortTimeLabel) · \(item.hit.format.shortTitle) · \(item.hit.court.shortName)"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                ActionButton(title: "Accept", style: .lime, height: 48, radius: 16, isLoading: working == "accept") { respond(accept: true) }
                ActionButton(title: "Decline", style: .quiet, height: 48, radius: 16, isLoading: working == "decline") { respond(accept: false) }
            }
            .disabled(working != nil)
        }
    }

    private var invite: some View {
        VStack(spacing: 12) {
            Button {
                navigate(.hit(item.hit.id))
            } label: {
                personRow(
                    title: "\(item.person.displayName) invited you",
                    subtitle: "\(item.hit.shortTimeLabel) · \(item.hit.format.shortTitle) · \(item.hit.court.shortName)"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                ActionButton(title: "I’m in", style: .lime, height: 48, radius: 16, isLoading: working == "claim") { claim() }
                ActionButton(title: "Not now", style: .quiet, height: 48, radius: 16, isLoading: working == "decline") { declineInvite() }
            }
            .disabled(working != nil)
        }
    }

    private var accepted: some View {
        HStack(spacing: 12) {
            Button { navigate(.player(item.person.id)) } label: { PlayerAvatar(card: item.person, size: 44) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.person.displayName), open profile")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.person.firstName) accepted you")
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.hit.shortTimeLabel) · \(item.hit.court.shortName)")
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button(action: openChat) {
                Text("Chat")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(CourtlyColor.blue))
                    .fixedSize()
            }
            .buttonStyle(PressableButtonStyle())
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { hits.dismissAccepted(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CourtlyColor.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    private func personRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            PlayerAvatar(card: item.person, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                // Two lines each, so "Christopher M. asked to join" keeps its verb on a small iPhone.
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ChevronMark()
        }
    }

    // MARK: - Actions

    private func respond(accept: Bool) {
        guard let requestID = item.requestId else { return }
        run(accept ? "accept" : "decline") {
            let hit = try await hits.respond(requestID: requestID, accept: accept)
            if accept { navigate(.hit(hit.id)) }
        }
    }

    private func claim() {
        guard let inviteID = item.inviteId else { return }
        run("claim") {
            let hit = try await hits.claimInvite(inviteID)
            navigate(.hit(hit.id))
        }
    }

    private func declineInvite() {
        guard let inviteID = item.inviteId else { return }
        run("decline") { try await hits.declineInvite(inviteID) }
    }

    private func openChat() {
        hits.dismissAccepted(item)
        if let chatID = item.hit.chatId {
            navigate(.chat(chatID))
        } else {
            navigate(.hit(item.hit.id))
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        guard working == nil else { return }
        working = label
        Task { @MainActor in
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            working = nil
        }
    }
}
