import SwiftUI

/// The Plan a hit form: when, where, what, how many spots, who can join.
/// Opened from a chat it becomes "Request a hit": the open spots go to that chat as a card.
/// Opened on a hit the viewer hosts it becomes "Edit hit", filled in with that hit.
/// Day and time are the court's wall clock: 6:30 PM means 6:30 PM where the court is.
struct PlanHitView: View {
    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let inviteChat: Chat?
    let editing: Hit?
    let onPosted: (Hit) -> Void

    init(inviteTo chat: Chat? = nil, onPosted: @escaping (Hit) -> Void) {
        inviteChat = chat
        editing = nil
        self.onPosted = onPosted
    }

    init(editing hit: Hit, onSaved: @escaping (Hit) -> Void) {
        inviteChat = nil
        editing = hit
        onPosted = onSaved
        // The pickers show device-zone dates; carry the court's wall clock over to them.
        let parts = hit.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: hit.startsAt)
        let local = Calendar.current.date(from: parts) ?? hit.startsAt
        _day = State(initialValue: Calendar.current.startOfDay(for: local))
        _time = State(initialValue: local)
        _duration = State(initialValue: hit.durationMin)
        _format = State(initialValue: hit.format)
        _spots = State(initialValue: hit.spotsTotal)
        _visibility = State(initialValue: hit.visibility)
        _court = State(initialValue: hit.court)
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

    /// The court's zone, so a hit planned while travelling still starts at the court's 6:30 PM.
    private var courtCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = court?.zone ?? .current
        return calendar
    }

    private var startsAt: Date {
        let device = Calendar.current
        var parts = device.dateComponents([.year, .month, .day], from: day)
        let clock = device.dateComponents([.hour, .minute], from: time)
        parts.hour = clock.hour ?? 18
        parts.minute = clock.minute ?? 30
        return courtCalendar.date(from: parts) ?? day
    }

    /// Players already in: the spots can't drop below them.
    private var playersIn: Int { editing?.players.filter { !$0.isHost }.count ?? 0 }

    /// "Times are Pacific Time, at the court" when the court is in another zone than this iPhone.
    private var zoneNote: String? {
        guard let zone = court?.zone,
              zone.secondsFromGMT(for: startsAt) != TimeZone.current.secondsFromGMT(for: startsAt) else { return nil }
        let name = zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? zone.identifier
        let yours = HitFormatting.string("EEE h:mm a", startsAt, in: .current)
        return "Times are \(name), where the court is. That's \(yours) your time."
    }

    private var hasChanges: Bool {
        guard let editing else { return true }
        return court?.id != editing.court.id || startsAt != editing.startsAt || duration != editing.durationMin
            || format != editing.format || spots != editing.spotsTotal || visibility != editing.visibility
    }

    private var tooSoon: Bool { startsAt <= Date.now.addingTimeInterval(15 * 60) }

    private var canPost: Bool {
        court != nil && !tooSoon && !isPosting && hasChanges
    }

    /// "Who can see my hits: Friends only" on You wins over the chip, so the chip says so.
    private var friendsOnlyProfile: Bool { session.profile?.hitVisibility == "friends" }

    /// When the request card stops taking claims: 8 PM the evening before, or two hours before
    /// the hit, whichever comes first. Never in the past.
    /// Only an expiry the host picked is sent; otherwise the server applies the same default rule.
    private var chosenExpiry: Date? {
        guard let customExpiry, customExpiry > .now, customExpiry < startsAt else { return nil }
        return customExpiry
    }

    private var inviteExpiry: Date {
        if let customExpiry, customExpiry > .now, customExpiry < startsAt { return customExpiry }
        let calendar = courtCalendar
        let eveningBefore = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: startsAt) ?? startsAt) ?? startsAt
        var expiry = min(startsAt.addingTimeInterval(-2 * 3600), eveningBefore)
        if expiry <= .now {
            expiry = min(startsAt.addingTimeInterval(-5 * 60), Date.now.addingTimeInterval(12 * 3600))
        }
        return expiry
    }

    private var postTitle: String {
        if editing != nil { return "Save changes" }
        return inviteChat.map { "Send to \($0.title)" } ?? "Post hit"
    }

    private var screenTitle: String {
        if editing != nil { return "Edit hit" }
        return inviteChat == nil ? "Plan a hit" : "Request a hit"
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    label("When", top: 16)
                    whenCard
                    if let zoneNote {
                        Text(zoneNote)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 4)
                    }
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
                                spots = max(Self.defaultSpots(for: option), playersIn)
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
                                .disabled(option == .anyone && friendsOnlyProfile)
                                .opacity(option == .anyone && friendsOnlyProfile ? 0.4 : 1)
                        }
                    }
                    if friendsOnlyProfile {
                        Text("Your hits are set to Friends only on the You tab.")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if tooSoon {
                    Text("Pick a time at least 15 minutes from now.")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if court == nil {
                    Text(editing == nil ? "Pick a court to post." : "Pick a court.")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if editing == nil {
                    SafetyNote()
                } else if hasChanges, playersIn > 0 || (editing?.pendingRequestCount ?? 0) > 0 {
                    Text("Players in the hit get a notification if the time or court changes.")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(title: postTitle, isEnabled: canPost, isLoading: isPosting, action: post)
            }
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
        .errorAlert($errorMessage, title: editing == nil ? "Couldn’t post the hit" : "Couldn’t save the hit")
    }

    // MARK: - Pieces

    private var navigationRow: some View {
        ZStack {
            Text(screenTitle)
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
            HStack {
                Button("Cancel") { dismiss() }
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.blue)
                    .disabled(isPosting)   // the hit is already on its way; closing now would hide where it went
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
                Text("Open until \(HitFormatting.string("EEE h:mm a", inviteExpiry, in: courtCalendar.timeZone))")
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
                .environment(\.timeZone, courtCalendar.timeZone)
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
                stepButton("−", enabled: spots > max(1, playersIn)) { spots -= 1 }
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
            guard editing == nil else { return await loadCourts() }
            if let first = session.profile?.formats.first {
                format = first
                spots = Self.defaultSpots(for: first)
            }
            if friendsOnlyProfile { visibility = .friends }
        }
        await loadCourts()
    }

    private func loadCourts() async {
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
                let hit: Hit
                if let editing {
                    hit = try await hits.update(
                        editing.id, courtID: court.id, startsAt: startsAt, durationMin: duration,
                        format: format, spots: spots, visibility: visibility
                    )
                    isPosting = false
                    dismiss()
                    onPosted(hit)
                    return
                }
                hit = try await hits.create(
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
