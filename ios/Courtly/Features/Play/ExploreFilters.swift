import SwiftUI

/// What Explore narrows the open hits by. Distance is the player's radius, so changing it here
/// changes it everywhere.
struct ExploreFilters: Equatable {
    enum When: String, CaseIterable, Identifiable {
        case any, today, tomorrow, weekend, week
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any day"
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .weekend: "This weekend"
            case .week: "This week"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case soonest, closest
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var when: When = .any
    var times: Set<AvailabilityMask.Block> = []
    var formats: Set<PlayFormat> = []
    var levels: Set<PlayerLevel> = []
    var sort: Sort = .soonest

    /// How many groups are narrowed, for the badge on the button.
    var activeCount: Int {
        [when != .any, !times.isEmpty, !formats.isEmpty, !levels.isEmpty, sort != .soonest].filter { $0 }.count
    }

    func apply(to hits: [Hit], calendar: Calendar = .current) -> [Hit] {
        let kept = hits.filter { hit in
            matchesDay(hit.startsAt, calendar: calendar)
                && (times.isEmpty || AvailabilityMask.slot(for: hit.startsAt, calendar: hit.calendar).map { times.contains($0.block) } == true)
                && (formats.isEmpty || formats.contains(hit.format))
                && (levels.isEmpty || hit.host.level.map { levels.contains($0) } == true)
        }
        switch sort {
        case .soonest: return kept.sorted { $0.startsAt < $1.startsAt }
        case .closest: return kept.sorted { ($0.miles ?? .infinity, $0.startsAt) < ($1.miles ?? .infinity, $1.startsAt) }
        }
    }

    private func matchesDay(_ date: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: .now)
        switch when {
        case .any: return true
        case .today: return calendar.isDateInToday(date)
        case .tomorrow: return calendar.isDateInTomorrow(date)
        case .week:
            guard let end = calendar.date(byAdding: .day, value: 7, to: today) else { return true }
            return date < end
        case .weekend:
            let weekday = calendar.component(.weekday, from: date)
            guard weekday == 1 || weekday == 7, let end = calendar.date(byAdding: .day, value: 8, to: today) else { return false }
            return date < end
        }
    }
}

/// The sheet behind the Filters button.
struct ExploreFiltersSheet: View {
    @Binding var filters: ExploreFilters
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExploreFilters
    @State private var radius: TravelRadius
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(filters: Binding<ExploreFilters>, radius: TravelRadius) {
        _filters = filters
        _draft = State(initialValue: filters.wrappedValue)
        _radius = State(initialValue: radius)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Reset") { draft = ExploreFilters(); radius = session.profile?.radius ?? .ten }
                    .disabled(draft == ExploreFilters() && radius == session.profile?.radius)
            }
            .font(.subheadline)
            .foregroundStyle(CourtlyColor.blue)
            .frame(minHeight: 44)
            Text("Filters")
                .font(.largeTitle.bold())
                .foregroundStyle(CourtlyColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("When") {
                        ForEach(ExploreFilters.When.allCases) { option in
                            chip(option.title, on: draft.when == option) { draft.when = option }
                        }
                    }
                    group("Time of day") {
                        ForEach(AvailabilityMask.Block.allCases) { block in
                            chip("\(block.title) · \(block.hoursLabel)", on: draft.times.contains(block)) { toggle(&draft.times, block) }
                        }
                    }
                    group("Format") {
                        ForEach(PlayFormat.allCases) { format in
                            chip(format.shortTitle, on: draft.formats.contains(format)) { toggle(&draft.formats, format) }
                        }
                    }
                    group("Host level") {
                        ForEach(PlayerLevel.allCases) { level in
                            chip(level.title, on: draft.levels.contains(level)) { toggle(&draft.levels, level) }
                        }
                    }
                    group("Distance") {
                        ForEach(TravelRadius.allCases) { option in
                            chip(option.title, on: radius == option) { radius = option }
                        }
                    }
                    group("Sort by") {
                        ForEach(ExploreFilters.Sort.allCases) { option in
                            chip(option.title, on: draft.sort == option) { draft.sort = option }
                        }
                    }
                    Text("Distance also updates your travel radius in Settings.")
                        .font(.footnote).foregroundStyle(CourtlyColor.secondary)
                        .padding(.top, 18)
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: "Show hits", style: .lime, compact: true, isLoading: isSaving, action: apply)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(CourtlyColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .errorAlert($errorMessage)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder chips: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(CourtlyFont.sectionHeader)
                .foregroundStyle(CourtlyColor.ink)
            FlowRow(spacing: 8) { chips() }
        }
        .padding(.top, 18)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CourtlyFont.captionSemibold)
                .foregroundStyle(on ? .white : CourtlyColor.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 13).fill(on ? CourtlyColor.blue : CourtlyColor.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func apply() {
        filters = draft
        guard radius != session.profile?.radius else { dismiss(); return }
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile(["radius_mi": radius.rawValue])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Chips that wrap onto the next line when the row is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
