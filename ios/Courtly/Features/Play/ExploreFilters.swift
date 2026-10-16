import CoreLocation
import SwiftUI

/// Local search controls, independent of profile preferences and calendar availability.
struct ExploreFilters: Equatable {
    enum When: String, CaseIterable, Identifiable {
        case any, today, tomorrow, week, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any day"
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .week: "This week"
            case .custom: "Choose dates"
            }
        }
    }
    enum TimeBlock: String, CaseIterable, Identifiable {
        case morning, afternoon, evening
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var hours: String {
            switch self { case .morning: "6–12"; case .afternoon: "12–5"; case .evening: "5–11" }
        }
        var minutes: Range<Int> {
            switch self { case .morning: 360..<720; case .afternoon: 720..<1020; case .evening: 1020..<1380 }
        }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case closest, soonest
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    enum Distance: Int, CaseIterable, Identifiable {
        case any = 0, five = 5, ten = 10, twentyFive = 25, fifty = 50, hundred = 100
        var id: Int { rawValue }
        var title: String { self == .any ? "Any distance" : "\(rawValue) mi" }
        func includes(_ miles: Double?) -> Bool {
            self == .any || miles.map { $0 <= Double(rawValue) } == true
        }
    }

    var distance: Distance = .any
    var when: When = .any
    var times: Set<TimeBlock> = []
    var formats: Set<PlayFormat> = []
    var levels: Set<PlayerLevel> = []
    var sort: Sort = .closest
    var firstDay = Calendar.current.startOfDay(for: Date.now)
    var lastDay = Calendar.current.startOfDay(for: Date.now)
    /// Minutes since local midnight at the court. End is exclusive.
    var exactTimes: Range<Int>?

    var activeCount: Int {
        [!formats.isEmpty, !levels.isEmpty, distance != .any].filter { $0 }.count
    }
    var timeSummary: String {
        let day = when == .custom ? "\(firstDay.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))" : when.title
        let time = exactTimes.map { "\(Self.clock($0.lowerBound))–\(Self.clock($0.upperBound))" }
            ?? (times.isEmpty ? "Any time" : TimeBlock.allCases.filter { times.contains($0) }.map(\.title).joined(separator: ", "))
        return "\(day) · \(time)"
    }
    static func clock(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minutes % 60)) \(hour < 12 ? "AM" : "PM")"
    }

    func apply(to hits: [Hit], friendIDs: Set<UUID> = [], now: Date = .now) -> [Hit] {
        let kept = hits.filter { hit in
            let minute = hit.calendar.component(.hour, from: hit.startsAt) * 60 + hit.calendar.component(.minute, from: hit.startsAt)
            return hit.startsAt > now && (hit.status == .open || hit.status == .confirmed)
                && distance.includes(hit.miles) && matchesDay(hit, now: now)
                && (exactTimes?.contains(minute) ?? (times.isEmpty || times.contains { $0.minutes.contains(minute) }))
                && (formats.isEmpty || formats.contains(hit.format))
                && (levels.isEmpty || hit.host.level.map { levels.contains($0) } == true)
        }
        func distanceKey(_ hit: Hit) -> Double { hit.miles.map { ($0 * 10).rounded() } ?? .infinity }
        func isFriend(_ hit: Hit) -> Bool { friendIDs.contains(hit.id) || hit.relationship(with: hit.host.id) == .friend }
        return kept.sorted { lhs, rhs in
            if sort == .soonest, lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if distanceKey(lhs) != distanceKey(rhs) { return distanceKey(lhs) < distanceKey(rhs) }
            if isFriend(lhs) != isFriend(rhs) { return isFriend(lhs) }
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func matchesDay(_ hit: Hit, now: Date) -> Bool {
        let calendar = hit.calendar
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: hit.startsAt)
        switch when {
        case .any: return true
        case .today: return day == today
        case .tomorrow: return day == calendar.date(byAdding: .day, value: 1, to: today)
        case .week:
            return day >= today && day < (calendar.date(byAdding: .day, value: 7, to: today) ?? today)
        case .custom:
            // Date pickers choose civil dates; apply those dates in each court's timezone.
            guard let start = calendar.date(from: Calendar.current.dateComponents([.year, .month, .day], from: firstDay)),
                  let end = calendar.date(from: Calendar.current.dateComponents([.year, .month, .day], from: lastDay)) else { return false }
            return day >= start && day <= end
        }
    }
}

enum ExploreInventory {
    static func hits(_ feed: PlayFeed, friendsOnly: Bool = false, area: HomeArea? = nil) -> [Hit] {
        var seen = Set<UUID>()
        let friendHosts = Set(feed.fromFriends.map { $0.host.id })
        return (feed.fromFriends + feed.nearYou).filter { hit in
            seen.insert(hit.id).inserted && (!friendsOnly || friendHosts.contains(hit.host.id) || hit.relationship(with: hit.host.id) == .friend)
        }.map { source in
            guard let area else { return source }
            var hit = source
            hit.miles = CLLocation(latitude: area.latitude, longitude: area.longitude)
                .distance(from: CLLocation(latitude: hit.court.lat, longitude: hit.court.lng)) / 1609.344
            return hit
        }
    }
}

struct ExploreFiltersSheet: View {
    @Binding var filters: ExploreFilters
    var inventory: [Hit] = []
    var friendIDs: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExploreFilters

    init(filters: Binding<ExploreFilters>, inventory: [Hit] = [], friendIDs: Set<UUID> = []) {
        _filters = filters
        _draft = State(initialValue: filters.wrappedValue)
        self.inventory = inventory
        self.friendIDs = friendIDs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose what fits").font(.title2.bold())
                    Button("Reset all") {
                        draft.formats = []; draft.levels = []; draft.distance = .any; draft.sort = .closest
                    }.font(.footnote.weight(.semibold)).foregroundStyle(CourtlyColor.blue).frame(minHeight: 44)
                    Text("Leave formats and levels blank to see all.").font(.caption).foregroundStyle(CourtlyColor.secondary)
                    ExploreChoiceGroup(title: "Format") {
                        ForEach(PlayFormat.allCases) { format in
                            ExploreChoice(title: format.shortTitle, selected: draft.formats.contains(format)) { toggle(&draft.formats, format) }
                        }
                    }
                    ExploreChoiceGroup(title: "Host level") {
                        ForEach(PlayerLevel.allCases) { level in
                            ExploreChoice(title: level.title, selected: draft.levels.contains(level)) { toggle(&draft.levels, level) }
                        }
                    }
                    ExploreChoiceGroup(title: "Distance") {
                        ExploreChoice(title: "Any distance", selected: draft.distance == .any) { draft.distance = .any }
                        Menu {
                            ForEach(ExploreFilters.Distance.allCases.filter { $0 != .any }) { distance in
                                Button(distance.title) { draft.distance = distance }
                            }
                        } label: {
                            ExploreChoiceFace(title: draft.distance == .any ? "Set a maximum" : "Within \(draft.distance.title)", selected: draft.distance != .any)
                        }
                    }
                    Text(draft.distance == .any ? "Includes hits beyond 50 miles." : "Measured from your search area.")
                        .font(.caption).foregroundStyle(CourtlyColor.secondary)
                    ExploreChoiceGroup(title: "Sort by") {
                        ForEach(ExploreFilters.Sort.allCases) { sort in
                            ExploreChoice(title: sort.title, selected: draft.sort == sort) { draft.sort = sort }
                        }
                    }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: resultTitle, style: .lime, compact: true) {
                    filters = draft; dismiss()
                }.accessibilityIdentifier("apply-filters").padding(.horizontal, 24).padding(.vertical, 12).background(.white)
            }
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .background(.white)
        }
        .tint(CourtlyColor.blue).foregroundStyle(CourtlyColor.ink)
        .preferredColorScheme(.light)
        .presentationDetents([.large])
    }
    private var resultTitle: String {
        let count = draft.apply(to: inventory, friendIDs: friendIDs).count
        return "Show \(count) \(count == 1 ? "hit" : "hits")"
    }
    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

struct ExploreSearchSheet: View {
    @Binding var filters: ExploreFilters
    @Binding var area: HomeArea?
    let homeArea: HomeArea?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExploreFilters
    @State private var draftArea: HomeArea?
    @State private var query: String
    @State private var lookingUp = false
    @State private var lookupError: String?

    init(filters: Binding<ExploreFilters>, area: Binding<HomeArea?>, homeArea: HomeArea?) {
        _filters = filters; _area = area; self.homeArea = homeArea
        _draft = State(initialValue: filters.wrappedValue)
        _draftArea = State(initialValue: area.wrappedValue)
        _query = State(initialValue: (area.wrappedValue ?? homeArea)?.label ?? "")
    }
    private var resolvedLabel: String { (draftArea ?? homeArea)?.label ?? "" }
    private var needsLookup: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines) != resolvedLabel }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Where and when?").font(.title.bold())
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LOCATION").font(.caption2.weight(.semibold)).foregroundStyle(CourtlyColor.secondary)
                        TextField("City, state or ZIP code", text: $query)
                            .font(.body.weight(.semibold)).submitLabel(.search)
                            .accessibilityIdentifier("search-area")
                            .onSubmit { Task { await lookup() } }
                            .onChange(of: query) { _, _ in lookupError = nil }
                        if lookingUp { ProgressView("Finding area…") }
                        else if needsLookup {
                            Button("Find area") { Task { await lookup() } }.frame(minHeight: 44)
                        } else {
                            Text("City or ZIP code").font(.footnote).foregroundStyle(CourtlyColor.blue)
                        }
                        if let lookupError { Text(lookupError).font(.footnote).foregroundStyle(CourtlyColor.red) }
                        if draftArea != nil, homeArea != nil {
                            Button("Use home area") { draftArea = nil; query = homeArea?.label ?? "" }.frame(minHeight: 44)
                        }
                    }.padding(16).background(CourtlyColor.surface, in: RoundedRectangle(cornerRadius: 18))
                    ExploreChoiceGroup(title: "Day") {
                        ForEach(ExploreFilters.When.allCases) { day in
                            ExploreChoice(title: day.title, selected: draft.when == day) { draft.when = day }
                        }
                    }
                    if draft.when == .custom {
                        DatePicker("From", selection: $draft.firstDay, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                            .onChange(of: draft.firstDay) { _, value in if draft.lastDay < value { draft.lastDay = value } }
                        DatePicker("Through", selection: $draft.lastDay, in: draft.firstDay..., displayedComponents: .date)
                    }
                    ExploreChoiceGroup(title: "Start time") {
                        ExploreChoice(title: "Any time", selected: draft.times.isEmpty && draft.exactTimes == nil) { draft.times = []; draft.exactTimes = nil }
                        ForEach(ExploreFilters.TimeBlock.allCases) { time in
                            ExploreChoice(title: "\(time.title) · \(time.hours)", selected: draft.exactTimes == nil && draft.times.contains(time)) {
                                draft.exactTimes = nil
                                if draft.times.contains(time) { draft.times.remove(time) } else { draft.times.insert(time) }
                            }
                        }
                    }
                    Button(draft.exactTimes == nil ? "Choose exact times" : "Use time blocks") {
                        draft.exactTimes = draft.exactTimes == nil ? 720..<1020 : nil
                        draft.times = []
                    }.frame(minHeight: 44)
                    if draft.exactTimes != nil {
                        DatePicker("From", selection: minuteBinding(start: true), displayedComponents: .hourAndMinute)
                        DatePicker("Before", selection: minuteBinding(start: false), displayedComponents: .hourAndMinute)
                        Text("Start times within this same-day window.").font(.caption).foregroundStyle(CourtlyColor.secondary)
                    }
                    Text("Times are local to the court.").font(.caption).foregroundStyle(CourtlyColor.secondary)
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Show hits", style: .lime, compact: true) {
                    Task {
                        if needsLookup { await lookup() }
                        guard !needsLookup, !lookingUp else { return }
                        filters = draft; area = draftArea; dismiss()
                    }
                }.disabled(lookingUp).padding(.horizontal, 24).padding(.vertical, 12).background(.white)
            }
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .background(.white)
        }
        .tint(CourtlyColor.blue).foregroundStyle(CourtlyColor.ink)
        .preferredColorScheme(.light)
        .presentationDetents([.large])
    }

    private func minuteBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = start ? draft.exactTimes?.lowerBound ?? 720 : draft.exactTimes?.upperBound ?? 1020
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            let minutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if start {
                let lower = min(minutes, 1438)
                draft.exactTimes = lower..<max(lower + 1, draft.exactTimes?.upperBound ?? 1020)
            } else {
                let upper = max(minutes, 1)
                draft.exactTimes = min(draft.exactTimes?.lowerBound ?? 720, upper - 1)..<upper
            }
        })
    }

    @MainActor private func lookup() async {
        guard !lookingUp else { return }
        let submitted = query
        lookingUp = true; lookupError = nil
        defer { lookingUp = false }
        do {
            let found = try await LocationService.area(matching: submitted)
            guard query == submitted else { return }
            draftArea = found; query = found.label
        } catch {
            guard query == submitted else { return }
            lookupError = "Couldn’t find that area. Try a city and state or a ZIP code."
        }
    }
}

private struct ExploreChoiceGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) { content }
        }
    }
}
private struct ExploreChoiceFace: View {
    let title: String
    let selected: Bool
    var body: some View {
        Text(title).font(.footnote.weight(.semibold))
            .foregroundStyle(selected ? .white : CourtlyColor.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 5)
            .background(selected ? CourtlyColor.blue : CourtlyColor.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
private struct ExploreChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { ExploreChoiceFace(title: title, selected: selected) }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
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
