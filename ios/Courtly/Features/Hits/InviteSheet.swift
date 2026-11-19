import MessageUI
import SwiftUI

/// Fill a hit's open spots. On top, friends and groups on Courtly: one tap sends the invite. Along the
/// bottom, ways to reach anyone else: copy the link, Messages, WhatsApp when installed, or the system sheet.
struct InviteSheet: View {
    let hit: Hit

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var groups: [Chat] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var sent: Set<UUID> = []
    @State private var sending: UUID?
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var copied = false
    @State private var showsMessages = false

    private var me: UUID? { session.profile?.id }

    private var matchingGroups: [Chat] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? groups : groups.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    private var matchingFriends: [Friend] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? friends : friends.filter { $0.card.displayName.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("Invite")
                    .font(.title.bold())
                    .foregroundStyle(CourtlyColor.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.blue)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            Text("\(hit.format.shortTitle) · \(hit.shortTimeLabel) · \(hit.court.shortName). First to accept takes the spot.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if loadFailed {
                        VStack(spacing: 12) {
                            QuietCard(title: "Couldn’t load your friends", detail: "Check your connection and try again. You can still share the link below.")
                            Button("Try again") { Task { await load() } }
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                        }
                    } else if groups.isEmpty && friends.isEmpty {
                        QuietCard(title: "No friends on Courtly yet", detail: "Share the link below. They can ask to join once they’re in.")
                    } else {
                        if groups.count + friends.count > 6 { searchField }
                        if matchingGroups.isEmpty && matchingFriends.isEmpty {
                            QuietCard(title: "No one by that name", detail: "Try another name, or share the link below.")
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 20) {
                                ForEach(matchingGroups) { group in
                                    tile(name: group.title, chatID: group.id, targetUserID: nil) { ChatAvatar(chat: group, me: me, size: 68) }
                                }
                                ForEach(matchingFriends) { friend in
                                    tile(name: friend.card.displayName, chatID: friend.dmChatId, targetUserID: friend.card.id) {
                                        PlayerAvatar(card: friend.card, size: 68)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }

            shareBar
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .task { await load() }
        .sheet(isPresented: $showsMessages) {
            MessageComposer(body: hit.shareText).ignoresSafeArea()
        }
        .errorAlert($errorMessage, title: "Couldn’t send the invite")
    }

    // MARK: - People on Courtly

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.secondary)
            TextField("Search", text: $query)
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CourtlyColor.card))
    }

    /// One person or group: tap to send, and the photo turns into a tick. A friend with no chat yet can't be sent to.
    private func tile<Avatar: View>(name: String, chatID: UUID?, targetUserID: UUID?, @ViewBuilder avatar: () -> Avatar) -> some View {
        let isSent = chatID.map(sent.contains) ?? false
        let isSending = chatID != nil && sending == chatID
        return Button {
            if let chatID { send(chatID: chatID, targetUserID: targetUserID) }
        } label: {
            VStack(spacing: 8) {
                avatar()
                    .frame(width: 68, height: 68)
                    .overlay {
                        if isSent {
                            Circle().fill(CourtlyColor.blue.opacity(0.88))
                            Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        } else if isSending {
                            Circle().fill(Color.black.opacity(0.35))
                            ProgressView().tint(.white)
                        }
                    }
                    .clipShape(Circle())
                Text(isSent ? "Sent" : name)
                    .font(CourtlyFont.captionSemibold)
                    .foregroundStyle(isSent ? CourtlyColor.blue : CourtlyColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if chatID == nil {
                    Text("Message first")
                        .font(.caption2)
                        .foregroundStyle(CourtlyColor.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(chatID == nil ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(chatID == nil || isSent || sending != nil)
        .accessibilityLabel(isSent ? "\(name), invite sent" : "Invite \(name)")
    }

    // MARK: - Everyone else

    /// Pinned along the bottom, the way share sheets in other apps are: the link reaches people who aren't on Courtly.
    private var shareBar: some View {
        VStack(spacing: 0) {
            HairlineSeparator()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    Button {
                        UIPasteboard.general.string = hit.shareURL.absoluteString
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    } label: {
                        target(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link", fill: CourtlyColor.card, tint: CourtlyColor.ink)
                    }
                    .accessibilityLabel("Copy link")
                    if MFMessageComposeViewController.canSendText() {
                        Button { showsMessages = true } label: {
                            target("Messages", systemImage: "message.fill", fill: Color(hex: 0x34C759), tint: .white)
                        }
                    }
                    if let whatsApp = Self.whatsAppURL(text: hit.shareText), UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!) {
                        Button { UIApplication.shared.open(whatsApp) } label: {
                            target("WhatsApp", systemImage: "phone.bubble.fill", fill: Color(hex: 0x25D366), tint: .white)
                        }
                    }
                    ShareLink(item: hit.shareURL, message: Text(hit.shareText)) {
                        target("More", systemImage: "square.and.arrow.up", fill: CourtlyColor.card, tint: CourtlyColor.ink)
                    }
                    .accessibilityLabel("More")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
        }
        .background(CourtlyColor.surface)
    }

    private func target(_ title: String, systemImage: String, fill: Color, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(CourtlyColor.line, lineWidth: fill == CourtlyColor.card ? 1 : 0))
            Text(title)
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.ink)
        }
        .frame(minWidth: 68)
        .contentShape(Rectangle())
    }

    private static func whatsAppURL(text: String) -> URL? {
        var parts = URLComponents(string: "whatsapp://send")
        parts?.queryItems = [URLQueryItem(name: "text", value: text)]
        return parts?.url
    }

    /// "Free Sunday" when the hit lands in a block they marked free, otherwise their level.
    private func friendDetail(_ card: PlayerCard) -> String {
        if let mask = card.availabilityMask, let slot = AvailabilityMask.slot(for: hit.startsAt, calendar: hit.calendar),
           AvailabilityMask(rawValue: mask).contains(day: slot.day, block: slot.block) {
            let weekday = hit.calendar.component(.weekday, from: hit.startsAt)
            return "Free \(hit.calendar.weekdaySymbols[weekday - 1])"
        }
        return card.levelAndArea.isEmpty ? "Friend" : card.levelAndArea
    }

    // MARK: - Data

    /// A failed load says so instead of looking like a player with no one to invite.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--hits-ui-checks") {
            friends = ["Ana Ruiz", "Luis Morales", "Priya Shah", "Marcus Lee", "Dev Patel"].enumerated().compactMap { index, name in
                let parts = name.split(separator: " ")
                let json = "{\"id\":\"\(UUID().uuidString)\",\"first_name\":\"\(parts[0])\",\"last_initial\":\"\(parts[1].prefix(1))\",\"hits_played\":3,\"formats\":[],\"level\":\"intermediate\"\(index == 4 ? "" : ",\"dm_chat_id\":\"\(UUID().uuidString)\"")}"
                return try? JSONCoding.decoder.decode(Friend.self, from: Data(json.utf8))
            }
            return
        }
        #endif
        async let friendList = API.People.friends()
        async let inbox = API.Chats.inbox()
        do {
            // Friends already in the hit can't be invited to it.
            let inHit = Set(hit.everyone.map(\.id))
            friends = try await friendList.filter { !inHit.contains($0.id) }
            groups = try await inbox.filter { $0.type == .group }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func send(chatID: UUID, targetUserID: UUID?) {
        sending = chatID
        Task { @MainActor in
            do {
                _ = try await API.Hits.sendInvite(hitID: hit.id, chatID: chatID, targetUserID: targetUserID)
                sent.insert(chatID)
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = nil
        }
    }
}

/// The system's own Messages composer, with the invitation already written.
private struct MessageComposer: UIViewControllerRepresentable {
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}
