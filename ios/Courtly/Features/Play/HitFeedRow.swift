import SwiftUI
import UIKit

/// One open hit. Tap to open it up: where, how long, who's in, and the button to ask.
struct HitFeedRow: View {
    let hit: Hit
    let isExpanded: Bool
    let onTap: () -> Void

    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @State private var isJoining = false
    @State private var showsPlayers = false
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
                        Button { showsPlayers = true } label: {
                            HStack(spacing: 10) {
                                AvatarStack(cards: hit.everyone, size: 26)
                                Text(playersLine)
                                    .font(CourtlyFont.secondary)
                                    .foregroundStyle(CourtlyColor.ink)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text("\(hit.dateText) · \(hit.clockText) · \(hit.durationMin) min")
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.ink)
                        Button(action: openInMaps) {
                            VStack(alignment: .leading, spacing: 1) {
                                if showsCourtName {
                                    Text(hit.court.name)
                                        .font(CourtlyFont.secondary)
                                        .foregroundStyle(CourtlyColor.ink)
                                }
                                Text(fullAddress)
                                    .font(CourtlyFont.secondary)
                                    .foregroundStyle(CourtlyColor.blue)
                            }
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open in Maps")
                    }
                    if let clash = clashingHit {
                        VStack(spacing: 8) {
                            Text("You’re already playing \(clash.shortTimeLabel)\(clash.counterpart(for: session.profile?.id).map { " with \($0.firstName)" } ?? "").")
                                .font(CourtlyFont.caption)
                                .foregroundStyle(CourtlyColor.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            ActionButton(title: "See that hit", style: .grouped) { navigate(.hit(clash.id)) }
                        }
                    } else if hit.hasPendingRequest {
                        ActionButton(title: "Requested", style: .grouped, isLoading: isJoining) { cancel() }
                    } else if hit.wasDeclined {
                        Text("\(hit.host.firstName) passed on this one.")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ActionButton(title: "Ask to join", isLoading: isJoining) { join() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showsPlayers) {
            PlayersSheet(title: "Who's in", players: hit.everyone) { id in
                showsPlayers = false
                navigate(.player(id))
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t ask to join")
    }

    /// An upcoming hit of yours that overlaps this one, if any. The backend refuses the ask anyway;
    /// showing it here saves the tap.
    private var clashingHit: Hit? {
        (hits.myHits?.upcoming ?? []).first { mine in
            mine.id != hit.id && mine.isMember && mine.isLive && mine.startsAt < hit.endsAt && mine.endsAt > hit.startsAt
        }
    }

    /// "Ana and Luis · 1 spot open"
    private var playersLine: String {
        let names = hit.everyone.prefix(2).map(\.firstName)
        let rest = hit.everyone.count - names.count
        let who: String
        switch (names.count, rest) {
        case (1, _): who = names[0]
        case (2, 0): who = "\(names[0]) and \(names[1])"
        default: who = "\(names.joined(separator: ", ")) and \(rest) more"
        }
        return "\(who) · \(hit.spotsLabel) open"
    }

    /// Street and city together; the name only when the court has one of its own.
    private var fullAddress: String {
        let parts = [hit.court.address, hit.court.city].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? hit.court.name : parts.joined(separator: ", ")
    }

    private var showsCourtName: Bool {
        !hit.court.name.isEmpty && hit.court.name != hit.court.address && hit.court.name != fullAddress
    }

    private func cancel() {
        guard let request = hit.viewer.request else { return }
        isJoining = true
        Task { @MainActor in
            do {
                try await hits.cancelRequest(request.id, hitID: hit.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
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
