import SwiftUI

/// The Plan a hit form: when, where, what, how many spots, who can join.
/// Opened from a chat it becomes "Request a hit": the open spots go to that chat as a card.
struct PlanHitView: View {
    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let inviteChat: Chat?
    let onPosted: (Hit) -> Void

    init(inviteTo chat: Chat? = nil, onPosted: @escaping (Hit) -> Void) {
        inviteChat = chat
        self.onPosted = onPosted
    }

    @State private var day = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    @State private var time = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now) ?? .now
    @State private var duration = 90
    @State private var format: PlayFormat = .casual
    @State private var spots = 1
    @State private var visibility: HitVisibility = .anyone
    @State private var court: Court?
    @State private var courts: [Court] = []
    @State private var expanded: Field?
    @State private var customExpiry: Date?
    @State private var showsExpiryPicker = false
    @State private var showsCourtPicker = false
    @State private var courtsError: String?
    @State private var isPosting = false
    @State private var didSeed = false
    @State private var errorMessage: String?

    private enum Field {
        case day, time
    }

    private static let lastCourtKey = "plan.lastCourtID"

    private var startsAt: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 18, minute: parts.minute ?? 30, second: 0, of: day) ?? day
    }

    private var canPost: Bool {
        court != nil && startsAt > Date.now.addingTimeInterval(15 * 60) && !isPosting
    }

    /// When the request card stops taking claims: 8 PM the evening before, or two hours before
    /// the hit, whichever comes first. Never in the past.
    /// Only an expiry the host picked is sent; otherwise the server applies the same default rule.
    private var chosenExpiry: Date? {
        guard let customExpiry, customExpiry > .now, customExpiry < startsAt else { return nil }
        return customExpiry
    }

    private var inviteExpiry: Date {
        if let customExpiry, customExpiry > .now, customExpiry < startsAt { return customExpiry }
        let calendar = Calendar.current
        let eveningBefore = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: startsAt) ?? startsAt) ?? startsAt
        var expiry = min(startsAt.addingTimeInterval(-2 * 3600), eveningBefore)
        if expiry <= .now {
            expiry = min(startsAt.addingTimeInterval(-5 * 60), Date.now.addingTimeInterval(12 * 3600))
        }
        return expiry
    }

    private var postTitle: String {
        inviteChat.map { "Send to \($0.title)" } ?? "Post hit"
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    label("When", top: 16)
                    whenCard
                    label("Where")
                    whereRow
                    if let courtsError, courts.isEmpty {
                        ErrorCaption(text: courtsError)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    label("What")
                    HStack(spacing: 8) {
                        ForEach(PlayFormat.allCases) { option in
                            Chip(title: option.shortTitle, isSelected: format == option) {
                                format = option
                                spots = Self.defaultSpots(for: option)
                            }
                        }
                    }
                    label("Spots to fill")
                    spotsRow
                    if inviteChat != nil {
                        expiryRow
                    }
                    label("Who can join")
                    HStack(spacing: 8) {
                        ForEach([HitVisibility.anyone, .friends]) { option in
                            Chip(title: option.title, isSelected: visibility == option) { visibility = option }
                        }
                    }
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: postTitle, isEnabled: canPost, isLoading: isPosting, action: post)
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(CourtlyColor.groupedBackground)
        }
        .sheet(isPresented: $showsCourtPicker) {
            CourtPickerView(courts: courts, selected: court) { picked in
                court = picked
                UserDefaults.standard.set(picked.id.uuidString, forKey: Self.lastCourtKey)
            }
        }
        .task { await seed() }
        .interactiveDismissDisabled(isPosting)
        .preferredColorScheme(.light)
        .errorAlert($errorMessage, title: "Couldn’t post the hit")
    }

    // MARK: - Pieces

    private var navigationRow: some View {
        ZStack {
            Text(inviteChat == nil ? "Plan a hit" : "Request a hit")
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
            HStack {
                Button("Cancel") { dismiss() }
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.blue)
                Spacer()
            }
        }
        .frame(height: 52)
        .padding(.horizontal, CourtlyMetrics.screenPadding)
    }

    private func label(_ title: String, top: CGFloat = 18) -> some View {
        SectionLabel(title: title)
            .padding(.top, top)
            .padding(.bottom, 8)
    }

    private var whenCard: some View {
        VStack(spacing: 0) {
            FormRow(title: "Day", value: HitFormatting.dayAndDate.string(from: day)) { toggle(.day) }
            if expanded == .day {
                DatePicker(
                    "Day",
                    selection: $day,
                    in: Date.now...(Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(CourtlyColor.blue)
                .padding(.horizontal, 8)
            }
            HairlineSeparator()
            FormRow(title: "Time", value: "\(HitFormatting.clock.string(from: time)) · \(duration) min") { toggle(.time) }
            if expanded == .time {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    ForEach([60, 90, 120], id: \.self) { minutes in
                        Button {
                            duration = minutes
                        } label: {
                            Text("\(minutes) min")
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(duration == minutes ? .white : CourtlyColor.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(duration == minutes ? CourtlyColor.blue : CourtlyColor.groupedBackground)
                                )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
        .clipShape(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous))
    }

    private var whereRow: some View {
        Button {
            showsCourtPicker = true
        } label: {
            HStack {
                Text(court?.name ?? "Choose a court")
                    .font(CourtlyFont.body)
                    .foregroundStyle(court == nil ? CourtlyColor.blue : CourtlyColor.ink)
                    .lineLimit(1)
                Spacer()
                ChevronMark()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var expiryRow: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open until \(HitFormatting.day.string(from: inviteExpiry)) \(HitFormatting.clock.string(from: inviteExpiry))")
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                Spacer()
                Button(showsExpiryPicker ? "Done" : "Change") {
                    withAnimation(.easeInOut(duration: 0.2)) { showsExpiryPicker.toggle() }
                }
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.blue)
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            if showsExpiryPicker, startsAt > Date.now.addingTimeInterval(60) {
                DatePicker(
                    "Open until",
                    selection: Binding(get: { inviteExpiry }, set: { customExpiry = $0 }),
                    in: Date.now...startsAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(CourtlyColor.blue)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
                .padding(.top, 8)
            }
        }
    }

    private var spotsRow: some View {
        HStack {
            Text(spots == 1 ? "1 player" : "\(spots) players")
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
            Spacer()
            HStack(spacing: 0) {
                stepButton("−", enabled: spots > 1) { spots -= 1 }
                Rectangle()
                    .fill(CourtlyColor.separator)
                    .frame(width: 1, height: 20)
                stepButton("+", enabled: spots < 7) { spots += 1 }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CourtlyColor.groupedBackground))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 22))
                .foregroundStyle(enabled ? CourtlyColor.blue : CourtlyColor.placeholder)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Behaviour

    private func toggle(_ field: Field) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded = expanded == field ? nil : field
        }
    }

    static func defaultSpots(for format: PlayFormat) -> Int {
        format == .doubles ? 3 : 1
    }

    private func seed() async {
        if !didSeed {
            didSeed = true
            if let first = session.profile?.formats.first {
                format = first
                spots = Self.defaultSpots(for: first)
            }
        }
        do {
            let list = try await API.Courts.nearby(limit: 30)
            courts = list
            courtsError = nil
            if court == nil {
                let lastID = UserDefaults.standard.string(forKey: Self.lastCourtKey).flatMap { UUID(uuidString: $0) }
                court = list.first { $0.id == lastID } ?? list.first
            }
        } catch {
            courtsError = "Couldn’t load nearby courts. \(error.localizedDescription)"
        }
    }

    private func post() {
        guard let court else { return }
        isPosting = true
        Task { @MainActor in
            do {
                let hit = try await hits.create(
                    courtID: court.id, startsAt: startsAt, durationMin: duration,
                    format: format, spots: spots, visibility: visibility,
                    inviteChatID: inviteChat?.id, inviteExpiresAt: inviteChat == nil ? nil : chosenExpiry
                )
                isPosting = false
                dismiss()
                onPosted(hit)
            } catch {
                isPosting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 48pt white row with a title and a blue value ("Day — Thu, Oct 16").
private struct FormRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.ink)
                Spacer()
                Text(value)
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.blue)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
