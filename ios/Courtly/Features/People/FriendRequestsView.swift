import SwiftUI

/// Friend requests waiting on you (confirm or delete), and the ones you sent (take back).
struct FriendRequestsView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    /// What's running per request: true = confirming, false = deleting or taking back.
    @State private var working: [UUID: Bool] = [:]
    @State private var errorMessage: String?

    private var requests: FriendRequests { inbox.requests ?? .empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if requests.incoming.isEmpty && requests.outgoing.isEmpty {
                    if inbox.requests == nil && inbox.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if inbox.requests == nil {
                        VStack(spacing: 12) {
                            QuietCard(title: "Couldn’t load requests", detail: "Check your connection and try again.")
                            Button("Try again") { Task { await inbox.load() } }
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                        }
                        .padding(.top, 24)
                    } else {
                        emptyState
                    }
                } else {
                    if !requests.incoming.isEmpty {
                        SectionHeader(title: requests.incoming.count == 1 ? "1 request" : "\(requests.incoming.count) requests", top: 8)
                        VStack(spacing: 16) {
                            ForEach(requests.incoming) { request in
                                Card(radius: 20) {
                                    VStack(spacing: 0) {
                                        row(request) { EmptyView() }
                                        HStack(spacing: 8) {
                                            ActionButton(title: "Confirm", style: .lime, isLoading: working[request.id] == true) { respond(request, accept: true) }
                                            ActionButton(title: "Delete", style: .grouped, isLoading: working[request.id] == false) { respond(request, accept: false) }
                                        }
                                        .disabled(working[request.id] != nil)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 16)
                                    }
                                }
                            }
                        }
                    }
                    if !requests.outgoing.isEmpty {
                        SectionHeader(title: "Sent", top: 24)
                        CardRows(items: requests.outgoing, radius: 22) { request in
                            row(request) {
                                PillButton(title: working[request.id] != nil ? "Cancelling…" : "Cancel", style: .tint) { cancel(request) }
                                    .fixedSize()
                                    .disabled(working[request.id] != nil)
                            }
                        }
                        Text("Waiting for them to confirm.")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle("Friend requests")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await inbox.load() }
        .task { await inbox.load() }
        .errorAlert($errorMessage)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No requests")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(CourtlyColor.ink)
            Text("When someone adds you, you’ll confirm them here.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
            Button {
                navigate(.addFriends)
            } label: {
                Text("Find friends")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.blue))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 64)
    }

    private func row<Actions: View>(_ request: FriendRequest, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 14) {
            Button {
                navigate(.player(request.id))
            } label: {
                HStack(spacing: 14) {
                    PlayerAvatar(card: request.card, size: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(request.card.displayName)
                            .font(CourtlyFont.bodySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle(request))
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actions()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func subtitle(_ request: FriendRequest) -> String {
        [request.mutualFriends.mutualLabel ?? request.card.levelAndArea, request.requestedAt.map(HitFormatting.inboxTime)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func respond(_ request: FriendRequest, accept: Bool) {
        working[request.id] = accept
        Task { @MainActor in
            defer { working[request.id] = nil }
            do {
                _ = try await API.People.respondFriendRequest(request.id, accept: accept)
                inbox.removeRequest(from: request.id)
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel(_ request: FriendRequest) {
        working[request.id] = false
        Task { @MainActor in
            defer { working[request.id] = nil }
            do {
                _ = try await API.People.cancelFriendRequest(request.id)
                inbox.removeRequest(from: request.id)
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// The small red count on the People header and the requests row, like a follow-request badge.
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 6 : 0)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(CourtlyColor.red))
                .overlay(Capsule().stroke(Color.white, lineWidth: 2))
        }
    }
}
