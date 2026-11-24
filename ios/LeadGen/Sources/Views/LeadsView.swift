import SwiftUI
import MapKit

// MARK: Filters

enum KindFilter: String, CaseIterable, Identifiable, Hashable, Codable {
    case all, forms, calls, missed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .forms: return "Forms"
        case .calls: return "Calls"
        case .missed: return "Missed"
        }
    }
    func matches(_ k: LeadKind) -> Bool {
        switch self {
        case .all: return true
        case .forms: return k == .form || k == .phone
        case .calls: return k == .call
        case .missed: return k == .missed
        }
    }
}

enum LeadStatusFilter: String, CaseIterable, Identifiable, Hashable, Codable {
    case all, open, filled, unrouted, exclusive, accepted, junk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .open: return "Open"
        case .filled: return "Filled"
        case .unrouted: return "Unrouted"
        case .exclusive: return "Exclusive"
        case .accepted: return "Accepted"
        case .junk: return "Junk"
        }
    }
    var color: Color {
        switch self {
        case .all, .exclusive: return Theme.violet
        case .open: return Theme.info
        case .filled, .accepted: return Theme.calls
        case .unrouted: return Theme.warn
        case .junk: return Theme.bad
        }
    }

    func matches(_ lead: Lead) -> Bool {
        switch self {
        case .all:
            return true
        case .junk:
            return lead.badLead == true
        case .open:
            let market = (lead.marketStatus ?? "").lowercased()
            let display = (lead.status ?? "").lowercased()
            return market == "open" || display == "open"
        case .filled:
            let market = (lead.marketStatus ?? "").lowercased()
            let display = (lead.status ?? "").lowercased()
            return market == "full" || market == "filled" || display == "filled"
        case .unrouted:
            if lead.cardKind == .unrouted || (lead.status ?? "").lowercased() == "unrouted" { return true }
            if lead.source == "directory-form" && lead.isUnassigned && lead.cardKind != .marketplace {
                let market = (lead.marketStatus ?? "").lowercased()
                return market.isEmpty || market == "none"
            }
            return false
        case .exclusive:
            if lead.cardKind == .exclusive { return true }
            if lead.cardKind == nil && lead.legacyKind != nil && lead.source != "directory-form" { return true }
            return false
        case .accepted:
            if (lead.acceptedCount ?? 0) > 0 { return true }
            if lead.recipientsSummary?.accepted.isEmpty == false { return true }
            let status = lead.status ?? ""
            return status == "won" || status == "won_unfinished" || status == "won_completed"
        }
    }
}

enum TradeDirectory {
    static let all: [(vertical: String, domain: String, name: String)] = [
        ("varmepump", "varmepumpinstallator.se", "Värmepumpinstallatör"),
        ("tak", "jamfortaklaggare.se", "Jämför takläggare"),
        ("badrum", "badrumsforetag.se", "Badrumsföretag"),
        ("bastubygge", "bastubyggare.se", "Bastubyggare"),
        ("arborist", "arboristtorget.se", "Arboristtorget"),
        ("dranering", "draneringsforetag.se", "Dräneringsföretag"),
        ("kranbil", "hyrkranbil.se", "Hyr kranbil"),
        ("bryggbyggare", "bryggbyggare.se", "Bryggbyggare"),
    ]

    static func label(_ vertical: String) -> String {
        all.first { $0.vertical.caseInsensitiveCompare(vertical) == .orderedSame }?.name
            ?? vertical.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct LeadFilter: Hashable, Codable {
    var clientId: String?
    var domain: String?
    var kind: KindFilter = .all
    var days = 90
    var showTests = false
    var vertical: String?
    var status: LeadStatusFilter = .all

    var sceneToken: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func fromScene(_ token: String) -> LeadFilter? {
        guard let data = token.data(using: .utf8), !data.isEmpty,
              var filter = try? JSONDecoder().decode(LeadFilter.self, from: data) else { return nil }
        if ![7, 30, 90, 365].contains(filter.days) { filter.days = 90 }
        return filter
    }

    func queryItems(search: String, cursor: String?, perPage: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "days", value: String(max(1, min(days, 365)))),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let domain, !domain.isEmpty {
            items.append(URLQueryItem(name: "domain", value: domain))
            items.append(URLQueryItem(name: "site", value: domain))
        }
        if let vertical, !vertical.isEmpty {
            items.append(URLQueryItem(name: "vertical", value: vertical))
        }
        switch status {
        case .all, .accepted, .junk:
            break
        case .filled:
            items.append(URLQueryItem(name: "status", value: "full"))
        case .open:
            items.append(URLQueryItem(name: "status", value: "open"))
        case .unrouted:
            items.append(URLQueryItem(name: "status", value: "unrouted"))
        case .exclusive:
            items.append(URLQueryItem(name: "status", value: "exclusive"))
        }
        if status == .junk {
            items.append(URLQueryItem(name: "include_bad", value: "1"))
        }
        items.append(URLQueryItem(name: "tests", value: showTests ? "include" : "hide"))
        if let clientId, !clientId.isEmpty {
            items.append(URLQueryItem(name: "client", value: clientId))
        }
        let q = search.trimmed
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return items
    }

    func allows(_ lead: Lead, now: Date = Date()) -> Bool {
        if lead.isDuplicate == true { return false }
        if !showTests && lead.isTestLead { return false }
        if status == .junk {
            if lead.badLead != true { return false }
        } else if lead.badLead == true {
            return false
        }
        if let domain, !domain.isEmpty, lead.domain?.lowercased() != domain.lowercased() { return false }
        if let vertical, !vertical.isEmpty, (lead.vertical ?? "").lowercased() != vertical.lowercased() { return false }
        if let clientId, lead.clientId != clientId { return false }
        if !kind.matches(lead.leadKind) { return false }
        if let date = lead.date, now.timeIntervalSince(date) > Double(days) * 86_400 { return false }
        return status.matches(lead)
    }
}

// MARK: Root

struct LeadsTab: View {
    @SceneStorage("leads.v1") private var saved = ""
    @State private var filter = LeadFilter()
    @State private var ready = false
    @Namespace private var ns

    var body: some View {
        NavigationStack {
            Group {
                if ready {
                    LeadCardsScreen(starting: filter, baseline: LeadFilter(), title: "Leads", isRoot: true, persist: true, saved: $saved)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .screenBackground()
                }
            }
            .appDestinations(ns)
        }
        .task {
            guard !ready else { return }
            if let restored = LeadFilter.fromScene(saved) { filter = restored }
            ready = true
        }
    }
}

struct LeadCardsScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.zoomNamespace) private var ns
    var title: String
    var isRoot: Bool
    var persist: Bool
    var baseline: LeadFilter
    @Binding var saved: String
    @State private var filter: LeadFilter
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var cards: [Lead] = []
    @State private var cursor: String?
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var generation = 0
    @State private var freshTick = 0
    @State private var filterTick = 0
    @State private var autoPages = 0
    @State private var showSites = false
    @State private var searchTask: Task<Void, Never>?
    @State private var siteOptions: [LeadSiteOption] = []
    @State private var apiVerticals: [String] = []
    @State private var totalCount: Int?

    init(starting: LeadFilter, baseline: LeadFilter, title: String, isRoot: Bool, persist: Bool = false, saved: Binding<String> = .constant("")) {
        self.title = title
        self.isRoot = isRoot
        self.persist = persist
        self.baseline = baseline
        _filter = State(initialValue: starting)
        _saved = saved
    }

    private var visible: [Lead] {
        let typed = query.trimmed
        // After the server answers `q`, keep its rows. Name and phone are not on the list.
        let trustServer = !submittedQuery.isEmpty && typed == submittedQuery
        return cards.filter { lead in
            guard filter.allows(lead) else { return false }
            if trustServer { return true }
            return lead.matchesSearch(typed)
        }
    }

    private var sections: [DaySection] {
        let cal = Calendar.current
        var map: [Date: [Lead]] = [:]
        for lead in visible {
            map[cal.startOfDay(for: lead.date ?? .distantPast), default: []].append(lead)
        }
        return map.keys.sorted(by: >).map { DaySection(day: $0, leads: map[$0] ?? []) }
    }

    private var verticalOptions: [String] {
        if !apiVerticals.isEmpty { return apiVerticals }
        var seen = TradeDirectory.all.map(\.vertical)
        for lead in cards {
            if let vertical = lead.vertical?.nilIfBlank, !seen.contains(where: { $0.caseInsensitiveCompare(vertical) == .orderedSame }) {
                seen.append(vertical)
            }
        }
        return seen
    }

    private var narrowed: Bool {
        filter.days != baseline.days || filter.status != baseline.status || filter.domain != baseline.domain
            || filter.vertical != baseline.vertical || filter.showTests != baseline.showTests
            || filter.clientId != baseline.clientId || filter.kind != baseline.kind || !query.trimmed.isEmpty
    }

    private var acceptedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let local = cards.filter { !$0.isTestLead && $0.accepted(since: start) }.count
        return max(local, store.acceptedToday)
    }

    var body: some View {
        List {
            if let errorText, !cards.isEmpty {
                Section {
                    ErrorBanner(message: errorText)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            if isLoading && cards.isEmpty {
                Section { SkeletonLeadCards(count: 6).padding(.vertical, 8) }
            } else if visible.isEmpty {
                Section { emptyState.listRowBackground(Color.clear) }
            } else {
                Section { summary }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.leads) { lead in
                            NavigationLink(value: lead) {
                                LeadCardRow(lead: lead)
                            }
                            .buttonStyle(.plain)
                            .zoomSource("lead-\(lead.id)", ns)
                            .leadActions(lead)
                            .onAppear {
                                guard lead.id == visible.last?.id else { return }
                                Task { await loadMore() }
                            }
                        }
                    } header: {
                        HStack {
                            Text(header(for: section.day))
                            Spacer()
                            Text("\(section.leads.count)")
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    }
                }
                if hasMore || isLoadingMore {
                    Section {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load more") { Task { await loadMore() } }
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Service, city, company or phone")
        .refreshable { await reload(pull: true) }
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isLoading && !cards.isEmpty { ProgressView() }
                overflowMenu
            }
        }
        .sheet(isPresented: $showSites) {
            SiteFilterSheet(domain: $filter.domain, cards: cards, options: siteOptions)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: filterTick)
        .sensoryFeedback(.selection, trigger: filterTick)
        .sensoryFeedback(.success, trigger: freshTick)
        .animation(.smooth(duration: 0.3), value: filter.sceneToken)
        .onChange(of: filter.sceneToken) { _, token in
            filterTick += 1
            autoPages = 0
            searchTask?.cancel()
            if submittedQuery.isEmpty, let cached = store.cachedLeadPage(for: token) {
                cards = dedupedLeads(cached.leads)
                cursor = cached.nextCursor
                hasMore = cached.hasMore
                rememberCatalog(cached)
            } else {
                cards = []
                cursor = nil
                hasMore = false
            }
            errorText = nil
            if persist { saved = token }
        }
        .onChange(of: query) { _, new in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                submittedQuery = new.trimmed
                await reload(pull: false)
            }
        }
        .task(id: filter.sceneToken) { await reload(pull: false) }
        .task(id: autoKey) {
            guard visible.isEmpty, hasMore, !cards.isEmpty, !isLoading, !isLoadingMore, autoPages < 8 else { return }
            autoPages += 1
            await loadMore()
        }
    }

    private var autoKey: String { "\(filter.sceneToken)|\(visible.count)|\(cards.count)|\(hasMore)" }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(summaryCount)
                    .font(.rounded(34))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(totalCount ?? visible.count)))
                Text(summaryCaption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if acceptedToday > 0 {
                Chip(text: "\(acceptedToday) accepted today", color: Theme.calls, symbol: "checkmark")
            }
            let calls = visible.filter { $0.leadKind == .call }.count
            let missed = visible.filter { $0.leadKind == .missed }.count
            if calls + missed > 0 {
                HStack(spacing: 14) {
                    legend("Calls", calls, Theme.calls)
                    legend("Missed", missed, Theme.missed)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private var summaryCount: String {
        if let totalCount, filter.status != .accepted, filter.status != .junk {
            return "\(totalCount)"
        }
        return hasMore ? "\(visible.count)+" : "\(visible.count)"
    }

    private var summaryCaption: String {
        if totalCount != nil, filter.status != .accepted, filter.status != .junk {
            return hasMore ? "in \(filter.days) days · \(cards.count) loaded" : "in \(filter.days) days"
        }
        return hasMore ? "loaded" : "in \(filter.days) days"
    }

    private func legend(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if filter.kind != .all {
                        ChipFace(title: filter.kind == .missed ? "Missed calls" : filter.kind.title, isOn: true, systemImage: "phone.fill", color: Theme.missed)
                    }
                    if let clientId = filter.clientId {
                        ChipFace(title: store.client(clientId)?.displayName ?? clientId, isOn: true, systemImage: "building.2.fill")
                    }
                    ForEach(LeadStatusFilter.allCases) { status in
                        Button {
                            filter.status = status
                        } label: {
                            ChipFace(title: status.title, isOn: filter.status == status, color: status.color)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([7, 30, 90, 365], id: \.self) { days in
                        Button {
                            filter.days = days
                        } label: {
                            ChipFace(title: days == 365 ? "1y" : "\(days)d", isOn: filter.days == days, systemImage: "calendar")
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Last \(days) days")
                    }
                    Button { showSites = true } label: {
                        ChipFace(title: filter.domain ?? "Site", isOn: filter.domain != nil, systemImage: "globe")
                    }
                    .buttonStyle(.pressable)
                    Menu {
                        Button("All trades") { filter.vertical = nil }
                        ForEach(verticalOptions, id: \.self) { vertical in
                            Button {
                                filter.vertical = vertical
                            } label: {
                                if filter.vertical?.lowercased() == vertical.lowercased() {
                                    Label(TradeDirectory.label(vertical), systemImage: "checkmark")
                                } else {
                                    Text(TradeDirectory.label(vertical))
                                }
                            }
                        }
                    } label: {
                        ChipFace(title: filter.vertical.map(TradeDirectory.label) ?? "Trade", isOn: filter.vertical != nil, systemImage: "square.grid.2x2")
                    }
                    Button {
                        filter.showTests.toggle()
                    } label: {
                        ChipFace(title: "Tests", isOn: filter.showTests, systemImage: "flask", color: Theme.warn)
                    }
                    .buttonStyle(.pressable)
                    if narrowed {
                        Button("Clear", action: clearFilters)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var overflowMenu: some View {
        Menu {
            Picker("Client", selection: $filter.clientId) {
                Text("All clients").tag(String?.none)
                ForEach(store.clients.filter { ($0.d30 ?? 0) > 0 || $0.clientId == filter.clientId }) { client in
                    Text(client.displayName).tag(Optional(client.clientId))
                }
            }
            Toggle("Show test leads", isOn: $filter.showTests)
            if narrowed {
                Divider()
                Button("Clear filters", role: .destructive, action: clearFilters)
            }
        } label: {
            Image(systemName: narrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("More filters")
    }

    @ViewBuilder
    private var emptyState: some View {
        let model = emptyCopy
        if !query.trimmed.isEmpty && errorText == nil {
            ContentUnavailableView.search(text: query.trimmed)
        } else if let action = model.action {
            EmptyState(symbol: model.symbol, title: model.title, message: model.message, tint: model.tint, actionTitle: action) {
                if action == "Try again" {
                    Task { await reload(pull: false) }
                } else if action == "Keep looking" {
                    Task { await loadMore() }
                } else {
                    clearFilters()
                }
            }
        } else {
            EmptyState(symbol: model.symbol, title: model.title, message: model.message, tint: model.tint)
        }
    }

    private var emptyCopy: (symbol: String, title: String, message: String, tint: Color, action: String?) {
        if let errorText, cards.isEmpty {
            return ("wifi.exclamationmark", "Could not load leads", errorText, Theme.warn, "Try again")
        }
        if visible.isEmpty && !cards.isEmpty && hasMore {
            return ("magnifyingglass", "No matches on this page", "More leads are still on the server.", Theme.violet, "Keep looking")
        }
        switch filter.status {
        case .open:
            return ("clock", "Nothing is waiting", "No marketplace lead is still open for companies in this filter.", Theme.info, narrowed ? "Clear filters" : nil)
        case .accepted:
            return ("checkmark.seal", "No accepts yet", "No company has accepted a lead in this window.", Theme.calls, narrowed ? "Clear filters" : nil)
        case .unrouted:
            return ("point.3.connected.trianglepath.dotted", "Nothing is unrouted", "Every lead here has a company, or there are no directory leads in this window.", Theme.warn, narrowed ? "Clear filters" : nil)
        case .junk:
            return ("trash", "No junk leads", "Bad leads stay out of the list until this filter is on.", Theme.bad, nil)
        case .filled:
            return ("person.3.fill", "No filled leads", "No lead has used all of its slots in this window.", Theme.calls, narrowed ? "Clear filters" : nil)
        case .exclusive:
            return ("tray", "No exclusive leads", "No rental-site leads match this filter.", Theme.violet, narrowed ? "Clear filters" : nil)
        case .all:
            return ("tray", "No leads in this filter", "Try a wider date range, or clear the site and trade.", Theme.violet, narrowed ? "Clear filters" : nil)
        }
    }

    private func clearFilters() {
        searchTask?.cancel()
        query = ""
        submittedQuery = ""
        filter = baseline
    }

    private func rememberCatalog(_ page: LeadPage) {
        if !page.sites.isEmpty { siteOptions = page.sites }
        if !page.verticals.isEmpty { apiVerticals = page.verticals }
        if let total = page.total { totalCount = total }
    }

    private func header(for day: Date) -> String {
        let cal = Calendar.current
        if day == .distantPast { return "No date" }
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func reload(pull: Bool) async {
        generation += 1
        let gen = generation
        let key = filter.sceneToken
        let searching = !submittedQuery.isEmpty
        if !pull && !searching {
            if let cached = store.cachedLeadPage(for: key) {
                cards = dedupedLeads(cached.leads)
                cursor = cached.nextCursor
                hasMore = cached.hasMore
                rememberCatalog(cached)
            } else {
                cards = []
                cursor = nil
                hasMore = false
            }
        }
        let previous = Set(cards.map(\.id))
        isLoading = true
        defer { if generation == gen { isLoading = false } }
        let path = Endpoint.path("/api/m/leads", filter.queryItems(search: submittedQuery, cursor: nil, perPage: 50))
        do {
            let (page, data) = try await store.leadPage(path)
            guard gen == generation else { return }
            let fresh = page.leads.contains { !previous.contains($0.id) }
            cards = dedupedLeads(page.leads)
            cursor = page.nextCursor
            hasMore = page.hasMore
            rememberCatalog(page)
            errorText = nil
            if !searching && persist {
                store.storeLeadPage(data, key: key)
            }
            if pull && fresh { freshTick += 1 }
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation else { return }
            let message = store.note(error)
            if !message.isEmpty { errorText = message }
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let gen = generation
        let path = Endpoint.path("/api/m/leads", filter.queryItems(search: submittedQuery, cursor: cursor, perPage: 50))
        do {
            let (page, _) = try await store.leadPage(path)
            guard gen == generation else { return }
            if page.leads.isEmpty || page.nextCursor == cursor {
                hasMore = false
                return
            }
            cards = dedupedLeads(cards + page.leads)
            self.cursor = page.nextCursor
            hasMore = page.hasMore && page.nextCursor != cursor
            rememberCatalog(page)
            errorText = nil
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation else { return }
            let message = store.note(error)
            if !message.isEmpty { errorText = message }
        }
    }
}

struct ChipFace: View {
    var title: String
    var isOn: Bool
    var systemImage: String? = nil
    var color: Color = Theme.violet

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .background {
            Capsule().fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
        }
        .overlay { Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 0.5) }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SiteFilterSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var domain: String?
    var cards: [Lead]
    var options: [LeadSiteOption] = []
    @State private var query = ""

    private struct Choice: Identifiable {
        var domain: String
        var title: String
        var id: String { domain }
    }

    private var choices: [Choice] {
        var seen = Set<String>()
        var rows: [Choice] = []
        func add(_ domain: String, _ title: String) {
            let key = domain.lowercased()
            guard seen.insert(key).inserted else { return }
            rows.append(Choice(domain: domain, title: title))
        }
        if options.isEmpty {
            for trade in TradeDirectory.all { add(trade.domain, trade.name) }
            for site in store.sites { add(site.domain, site.name?.nilIfBlank ?? site.domain) }
        } else {
            for site in options { add(site.domain, site.siteName?.nilIfBlank ?? site.domain) }
        }
        for lead in cards {
            if let domain = lead.domain?.nilIfBlank { add(domain, lead.siteName?.nilIfBlank ?? domain) }
        }
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.domain.lowercased().contains(q) || $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    domain = nil
                    dismiss()
                } label: {
                    row("All sites", selected: domain == nil)
                }
                Section("Sites") {
                    ForEach(choices) { choice in
                        Button {
                            domain = choice.domain
                            dismiss()
                        } label: {
                            row(choice.title, caption: choice.title == choice.domain ? nil : choice.domain, selected: domain?.lowercased() == choice.domain.lowercased())
                        }
                    }
                }
            }
            .navigationTitle("Site")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Domain or name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, caption: String? = nil, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.violet)
            }
        }
    }
}

// MARK: Card

struct LeadCardRow: View {
    var lead: Lead

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Chip(text: lead.badgeText, color: lead.badgeColor, symbol: lead.leadKind.symbol)
                if lead.isTestLead { Chip(text: "Test", color: Theme.warn) }
                Spacer(minLength: 8)
                Text(Fmt.time(lead.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(lead.cardTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(lead.cardSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Chip(text: lead.pillText, color: lead.pillColor)
                if let price = lead.priceText {
                    Text(price)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                if let billing = lead.billingText {
                    Chip(text: billing, color: lead.billingColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.recipientBar)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(lead.recipientCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lead.pillColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Swipe

struct LeadActions: ViewModifier {
    var lead: Lead
    @Environment(\.openURL) private var openURL

    @ViewBuilder
    func body(content: Content) -> some View {
        if lead.contactIsMasked {
            content
        } else {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if let url = Fmt.telURL(lead.phone) {
                        Button { openURL(url) } label: { Label("Call", systemImage: "phone.fill") }
                            .tint(Theme.calls)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let url = Fmt.mailURL(lead.email) {
                        Button { openURL(url) } label: { Label("Email", systemImage: "envelope.fill") }
                            .tint(Theme.info)
                    }
                    if let url = Fmt.smsURL(lead.phone) {
                        Button { openURL(url) } label: { Label("Message", systemImage: "message.fill") }
                            .tint(Theme.violet)
                    }
                }
                .leadContextMenu(lead)
        }
    }
}

struct LeadContextMenu: ViewModifier {
    var lead: Lead
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.contextMenu {
            if !lead.contactIsMasked {
                if let url = Fmt.telURL(lead.phone) {
                    Button { openURL(url) } label: { Label("Call", systemImage: "phone") }
                }
                if let url = Fmt.smsURL(lead.phone) {
                    Button { openURL(url) } label: { Label("Message", systemImage: "message") }
                }
                if let url = Fmt.mailURL(lead.email) {
                    Button { openURL(url) } label: { Label("Email", systemImage: "envelope") }
                }
                if let p = lead.phone?.nilIfBlank {
                    Button { UIPasteboard.general.string = p } label: { Label("Copy Number", systemImage: "doc.on.doc") }
                }
                if let e = lead.email?.nilIfBlank {
                    Button { UIPasteboard.general.string = e } label: { Label("Copy Email", systemImage: "doc.on.doc") }
                }
            }
        }
    }
}

struct DaySection: Identifiable {
    var day: Date
    var leads: [Lead]
    var id: Date { day }
}

extension View {
    func leadActions(_ lead: Lead) -> some View { modifier(LeadActions(lead: lead)) }
    func leadContextMenu(_ lead: Lead) -> some View { modifier(LeadContextMenu(lead: lead)) }
}

private func dedupedLeads(_ rows: [Lead]) -> [Lead] {
    var seen = Set<String>()
    var out: [Lead] = []
    for lead in rows.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) where seen.insert(lead.id).inserted {
        out.append(lead)
    }
    return out
}

// MARK: Detail

private enum TimelinePicture {
    case full([LeadRecipient])
    case own([LeadRecipient], others: Int)
    case hidden(Int)
}

struct LeadDetailView: View {
    @Environment(AppStore.self) private var store
    var lead: Lead
    @State private var copied = 0
    @State private var place: LeadPlace?
    @State private var celebrate = 0

    private var payload: LeadDetailPayload? { store.leadDetails[lead.id] }

    private var shown: Lead {
        guard let payload else { return lead }
        return lead.overlaying(payload.lead)
    }

    private var recipients: [LeadRecipient] {
        // Detail returns recipients oldest first. Keep that order.
        let decoded = payload?.recipients ?? []
        if !decoded.isEmpty { return decoded }
        let inline = shown.inlineRecipients ?? []
        if !inline.isEmpty { return inline }
        return shown.syntheticRecipients()
    }

    private var timeline: TimelinePicture {
        if shown.visibility == "teaser" {
            return .hidden(shown.otherOfferedCount ?? 0)
        }
        if shown.visibility == "accepted" {
            return .own([], others: shown.otherOfferedCount ?? 0)
        }
        let all = recipients
        guard !shown.isAdminViewer else { return .full(all) }
        let own = all.filter { row in
            if row.isSelf == true { return true }
            if let id = shown.viewerClientId, row.clientId == id { return true }
            return false
        }
        let others = max(all.count - own.count, 0)
        if own.isEmpty { return .hidden(all.count) }
        return .own(own, others: others)
    }

    private var acceptedRecently: Bool {
        let start = Date().addingTimeInterval(-86_400)
        if shown.accepted(since: start) { return true }
        return recipients.contains { $0.displayStatus == "accepted" && (Fmt.parse($0.acceptedAt) ?? .distantPast) >= start }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                priceCard
                if !shown.contactIsMasked { actionRow }
                if let place { MapCard(place: place) }
                timelineCard
                if let text = safeDescription(shown.detailText) { descriptionCard(text) }
                if !safeFields.isEmpty { fieldsCard }
                if let timing = shown.timing?.nilIfBlank { metaLine("Timing", timing) }
                contactSection
                if let message = shown.message?.nilIfBlank, !shown.contactIsMasked { messageCard(message) }
                detailsCard
                if let note = (payload?.note ?? shown.billingNote)?.nilIfBlank { metaLine("Billing", note) }
                if let notes = shown.notes?.nilIfBlank, !shown.contactIsMasked {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text").font(.headline)
                        Text(notes).textSelection(.enabled)
                    }
                    .card()
                }
                if store.leadDetailFailed.contains(lead.id) {
                    Text("The live timeline didn’t load. Showing what is already on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground(shown.pillColor)
        .navigationTitle(shown.cardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
        .sensoryFeedback(.impact(weight: .medium), trigger: celebrate)
        .task(id: lead.id) {
            await store.loadLeadDetail(lead.id)
            let resolved = await LeadPlace.resolve(for: shown, site: store.site(shown.domain))
            withAnimation(.smooth) { place = resolved }
            if celebrate == 0 && acceptedRecently { celebrate = 1 }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Chip(text: shown.badgeText, color: shown.badgeColor, symbol: shown.leadKind.symbol)
            Text(shown.cardTitle)
                .font(.rounded(30))
                .multilineTextAlignment(.center)
            Text(shown.cardSubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Chip(text: shown.pillText, color: shown.pillColor)
                if shown.isTestLead { Chip(text: "Test", color: Theme.warn) }
                if shown.badLead == true { Chip(text: "Junk", color: Theme.bad) }
            }
            if let date = shown.date {
                Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())) · \(Fmt.relative(date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(shown.priceText ?? "No price")
                    .font(.rounded(28))
                    .monospacedDigit()
                Spacer()
                if let billing = shown.billingText {
                    Chip(text: billing, color: shown.billingColor)
                }
            }
            if let max = shown.slots?.max, max > 0 {
                let won = shown.slots?.won ?? shown.acceptedCount ?? 0
                let left = shown.slotsLeft ?? max(0, max - won)
                Text("\(won) of \(max) slots filled · \(left) left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let text = shown.billing?.text?.nilIfBlank {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let teaser = shown.calculatorTeaser?.nilIfBlank {
                Text(teaser)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Call", symbol: "phone.fill", tint: Theme.calls, url: Fmt.telURL(shown.phone))
            ActionButton(title: "Mail", symbol: "envelope.fill", tint: Theme.info, url: Fmt.mailURL(shown.email))
            ActionButton(title: "Message", symbol: "message.fill", tint: Theme.violet, url: Fmt.smsURL(shown.phone))
            ActionButton(title: "Site", symbol: "safari.fill", tint: .gray, url: shown.domain.flatMap { URL(string: "https://\($0)") })
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Companies", systemImage: "person.3.sequence.fill")
                .font(.headline)
            switch timeline {
            case .full(let rows):
                if rows.isEmpty { timelineEmpty } else { timelineList(rows) }
            case .own(let rows, let others):
                if rows.isEmpty {
                    Text(shown.offerStatus.map { "Your offer is \(LeadRecipient.statusTitle(for: $0))." } ?? "You accepted this lead.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    timelineList(rows)
                }
                if others > 0 {
                    Text("\(others) other \(others == 1 ? "firm was" : "firms were") also offered this lead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .hidden(let count):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Companies hidden", systemImage: "eye.slash")
                        .font(.subheadline.weight(.semibold))
                    Text(count > 0
                         ? "\(count) \(count == 1 ? "company was" : "companies were") offered this lead. Names stay hidden until you accept."
                         : "Company names stay hidden until you accept.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var timelineEmpty: some View {
        Text(emptyTimeline)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var emptyTimeline: String {
        if shown.cardKind == .marketplace || shown.source == "directory-form" || shown.cardKind == .unrouted {
            return "No company has been offered this lead yet. It is still waiting."
        }
        if shown.isUnassigned {
            return "No client is attached. This site is unrented."
        }
        return "No delivery has been recorded."
    }

    private func timelineList(_ rows: [LeadRecipient]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                timelineRow(row, isLast: index == rows.count - 1)
            }
        }
    }

    private func timelineRow(_ row: LeadRecipient, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: row.statusSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(row.statusColor)
                    .frame(width: 28, height: 28)
                    .background(row.statusColor.opacity(0.14), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2, height: 36)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.companyTitle)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Chip(text: row.statusTitle, color: row.statusColor)
                }
                if let line = row.priceLine {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if shown.isAdminViewer, let email = row.email?.nilIfBlank, let url = Fmt.mailURL(email) {
                    Link(email, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
                ForEach(row.stampLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private func descriptionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About the job", systemImage: "text.alignleft")
                .font(.headline)
            Text(text).textSelection(.enabled)
        }
        .card()
    }

    private var safeFields: [LeadField] {
        let fields = payload?.fields ?? []
        guard shown.contactIsMasked else { return fields }
        let banned = ["name", "namn", "phone", "telefon", "email", "e-post", "epost", "mail", "message", "meddelande"]
        return fields.filter { field in
            let label = field.label.lowercased()
            return !banned.contains { label.contains($0) }
        }
    }

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Details", systemImage: "list.bullet")
                .font(.headline)
            ForEach(safeFields) { field in
                HStack(alignment: .firstTextBaseline) {
                    Text(field.label).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(field.value).fontWeight(.medium).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func metaLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
        .card()
    }

    @ViewBuilder
    private var contactSection: some View {
        if shown.contactIsMasked {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.violet)
                    .frame(width: 52, height: 52)
                    .background(Theme.violet.opacity(0.12), in: Circle())
                Text("Contact hidden")
                    .font(.headline)
                Text("Name, phone, email and the message stay hidden until this company accepts the lead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Contact", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Spacer()
                    Text("Only you")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.violet)
                }
                if payload == nil && !store.leadDetailFailed.contains(lead.id) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading contact")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if shown.name == nil && shown.phone == nil && shown.email == nil {
                    Text("No contact details on this lead.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let name = shown.name?.nilIfBlank {
                    contactLine(symbol: "person.fill", tint: Theme.violet, label: "Name", value: name, url: nil, copy: name)
                }
                if let phone = shown.phone?.nilIfBlank {
                    contactLine(symbol: "phone.fill", tint: Theme.calls, label: "Phone", value: Fmt.phone(phone), url: Fmt.telURL(phone), copy: phone)
                }
                if let email = shown.email?.nilIfBlank {
                    contactLine(symbol: "envelope.fill", tint: Theme.info, label: "Email", value: email, url: Fmt.mailURL(email), copy: email)
                }
            }
            .card()
        }
    }

    private func contactLine(symbol: String, tint: Color, label: String, value: String, url: URL?, copy: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let url {
                    Link(value, destination: url).font(.body.weight(.medium)).lineLimit(1)
                } else {
                    Text(value).font(.body.weight(.medium)).lineLimit(1).textSelection(.enabled)
                }
            }
            Spacer()
            Button {
                UIPasteboard.general.string = copy
                copied += 1
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(label)")
        }
    }

    private func messageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Message", systemImage: "text.bubble.fill")
                .font(.headline)
                .foregroundStyle(shown.pillColor)
            Text(message)
                .font(.body)
                .textSelection(.enabled)
        }
        .card()
    }

    private func safeDescription(_ text: String?) -> String? {
        guard let text = text?.nilIfBlank else { return nil }
        guard shown.contactIsMasked else { return text }
        if text.contains("@") { return nil }
        if text.filter(\.isNumber).count >= 6 { return nil }
        return text
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if shown.cardKind != .marketplace, let client = store.client(shown.clientId) {
                NavigationLink(value: client) {
                    detailRow("Client", client.displayName, symbol: "building.2.fill", link: true)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            } else if shown.cardKind != .marketplace, let name = shown.client?.nilIfBlank {
                detailRow("Client", shown.isUnassigned ? "No client yet" : name, symbol: "building.2.fill")
                Divider().padding(.leading, 16)
            }
            if let domain = shown.domain?.nilIfBlank {
                if let site = store.site(domain) {
                    NavigationLink(value: site) { detailRow("Site", domain, symbol: "globe", link: true) }
                        .buttonStyle(.plain)
                } else {
                    detailRow("Site", domain, symbol: "globe")
                }
                Divider().padding(.leading, 16)
            }
            detailRow("Source", Fmt.sourceLabel(shown.source), symbol: "arrow.down.forward.circle")
            if let status = shown.status?.nilIfBlank, shown.cardKind != .marketplace {
                Divider().padding(.leading, 16)
                detailRow("CRM", Fmt.statusLabel(status), symbol: "circle.grid.2x2")
            }
            if let duration = Fmt.duration(shown.durationS) {
                Divider().padding(.leading, 16)
                detailRow("Call length", duration, symbol: "timer")
            }
            if let follow = shown.followUpDate {
                Divider().padding(.leading, 16)
                detailRow("Follow up", Fmt.shortDate(follow), symbol: "calendar.badge.clock")
            }
            if let value = shown.wonValueSek, value > 0 {
                Divider().padding(.leading, 16)
                detailRow("Won value", Fmt.sek(value), symbol: "trophy.fill")
            }
            if let reference = shown.masterExternalId?.nilIfBlank {
                Divider().padding(.leading, 16)
                detailRow("Reference", reference, symbol: "number")
            }
        }
        .card(padding: 4)
    }

    private func detailRow(_ label: String, _ value: String, symbol: String, link: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(link ? Theme.violet : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if link {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct ActionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(url == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white))
                    .frame(width: 48, height: 48)
                    .background(url == nil ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(tint.gradient), in: Circle())
                    .shadow(color: url == nil ? .clear : tint.opacity(0.35), radius: 8, y: 4)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(url == nil ? .tertiary : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(url == nil)
    }
}

// MARK: Map

struct LeadPlace: Equatable {
    var name: String
    var coordinate: CLLocationCoordinate2D

    static func == (a: LeadPlace, b: LeadPlace) -> Bool {
        a.name == b.name && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }

    static func guessName(for lead: Lead, site: Site?) -> String? {
        for line in (lead.message ?? "").split(separator: "\n") {
            let lower = line.lowercased()
            for key in ["kommun:", "ort:", "stad:", "postort:", "adress:", "address:"] where lower.hasPrefix(key) {
                let value = String(line.dropFirst(key.count)).trimmed
                if !value.isEmpty { return value }
            }
        }
        if let name = site?.name?.trimmed, let last = name.split(separator: " ").last, last.count > 2, last.first?.isUppercase == true {
            return String(last)
        }
        return nil
    }

    static func resolve(for lead: Lead, site: Site?) async -> LeadPlace? {
        guard let name = lead.inferredLocation ?? guessName(for: lead, site: site) else { return nil }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(name), Sverige"
        req.resultTypes = .address
        guard let resp = try? await MKLocalSearch(request: req).start(),
              let item = resp.mapItems.first else { return nil }
        return LeadPlace(name: name, coordinate: item.placemark.coordinate)
    }
}

struct MapCard: View {
    var place: LeadPlace
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            let q = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place.name
            if let url = URL(string: "https://maps.apple.com/?q=\(q)&ll=\(place.coordinate.latitude),\(place.coordinate.longitude)") {
                openURL(url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)),
                    interactionModes: []) {
                    Marker(place.name, systemImage: "mappin", coordinate: place.coordinate)
                        .tint(Theme.violet)
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text(place.name)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
        }
        .buttonStyle(.pressable)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: Display

extension Lead {
    var badgeText: String {
        if let vertical = vertical?.nilIfBlank { return TradeDirectory.label(vertical) }
        if let name = siteName?.nilIfBlank { return name }
        if let domain = domain?.nilIfBlank { return domain }
        return Fmt.sourceLabel(source)
    }

    var badgeColor: Color { Theme.avatarColors(badgeText).first ?? Theme.violet }

    var cardTitle: String {
        inferredService ?? siteName?.nilIfBlank ?? domain?.nilIfBlank ?? Fmt.sourceLabel(source)
    }

    var cardSubtitle: String {
        var parts: [String] = []
        if let domain = domain?.nilIfBlank, domain.caseInsensitiveCompare(cardTitle) != .orderedSame {
            parts.append(domain)
        }
        if let location = inferredLocation { parts.append(location) }
        if parts.isEmpty, let client = client?.nilIfBlank, !isUnassigned { parts.append(client) }
        return parts.isEmpty ? Fmt.sourceLabel(source) : parts.joined(separator: " · ")
    }

    var pillText: String {
        if badLead == true { return "Junk" }
        switch (status ?? "").lowercased() {
        case "open": return "Open"
        case "filled", "full": return "Filled"
        case "closed": return "Closed"
        case "unrouted": return "Unrouted"
        case "unassigned": return "Unassigned"
        case "marketplace": return "Marketplace"
        case "new", "":
            if cardKind == .exclusive || (cardKind == nil && legacyKind != nil && source != "directory-form") { return "Exclusive" }
            if cardKind == .unrouted { return "Unrouted" }
            return "New"
        default:
            return Fmt.statusLabel(status)
        }
    }

    var pillColor: Color {
        switch pillText {
        case "Junk": return Theme.bad
        case "Open", "Offered": return Theme.info
        case "Filled", "Accepted": return Theme.calls
        case "Unrouted", "Unassigned", "Unrented": return Theme.warn
        case "Closed": return .gray
        case "Own": return Theme.deepViolet
        case "Exclusive": return Theme.violet
        default: return Fmt.statusColor(status)
        }
    }

    var priceText: String? {
        guard let priceSek, priceSek > 0 else { return nil }
        return Fmt.sek(priceSek)
    }

    var billingText: String? {
        switch billing?.mark {
        case "billed": return "Billed"
        case "free": return "Free"
        case "mixed": return "Billed · Free"
        case "not_billed": return "Not billed"
        case "unset": return nil
        default:
            break
        }
        let billed = (billableCount ?? 0) > 0 || billable == true
        let free = (freeCount ?? 0) > 0 || freeLead == true
        if billed && free { return "Billed · Free" }
        if billed { return "Billed" }
        if free { return "Free" }
        if cardKind == .marketplace { return "Not billed" }
        return nil
    }

    var buckets: (accepted: Int, offered: Int, queued: Int, declined: Int) {
        if let counts = recipientsSummary?.counts {
            return (counts.accepted, counts.offered, counts.queued, counts.declined)
        }
        return (acceptedCount ?? 0, offeredCount ?? 0, queuedCount ?? slots?.queued ?? 0, 0)
    }

    var billingColor: Color {
        guard let billingText else { return .gray }
        if billingText == "Billed" { return Theme.calls }
        if billingText == "Billed · Free" { return Theme.violet }
        if billingText.hasPrefix("Free") { return Theme.warn }
        return .gray
    }

    var recipientBar: String {
        let bucket = buckets
        var parts: [String] = []
        if let name = recipientsSummary?.accepted.first?.name?.nilIfBlank {
            parts.append("\(name) accepted")
        } else if bucket.accepted > 0 {
            parts.append("\(bucket.accepted) accepted")
        }
        if bucket.offered > 0 { parts.append("\(bucket.offered) offered") }
        if bucket.queued > 0 { parts.append("\(bucket.queued) queued") }
        if bucket.declined > 0 { parts.append("\(bucket.declined) declined") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if !isUnassigned, let client = client?.nilIfBlank { return "Delivered to \(client)" }
        return "No company yet"
    }

    var recipientCountText: String {
        let bucket = buckets
        var total = bucket.accepted + bucket.offered + bucket.queued + bucket.declined
        if total == 0 && !isUnassigned { total = 1 }
        let noun = total == 1 ? "recipient" : "recipients"
        if cardKind == .exclusive || (cardKind == nil && legacyKind != nil && source != "directory-form" && !isUnassigned) {
            return "\(total) \(noun) · Delivered"
        }
        return "\(total) \(noun) · \(bucket.accepted) accepted"
    }

    func matchesSearch(_ raw: String) -> Bool {
        let q = raw.trimmed.lowercased()
        if q.isEmpty { return true }
        var bits: [String?] = [client, domain, siteName, service, location, vertical, detailText, inferredService, inferredLocation, source, masterExternalId, badgeText, cardTitle]
        if !contactIsMasked {
            bits.append(contentsOf: [name, phone, email, message])
        }
        if bits.compactMap({ $0?.lowercased() }).contains(where: { $0.contains(q) }) { return true }
        let names = (recipientsSummary?.accepted.compactMap(\.name) ?? []) + (recipientsSummary?.offeredNames ?? []) + (recipientsSummary?.queuedNames ?? [])
        if names.contains(where: { $0.lowercased().contains(q) }) { return true }
        let digits = q.filter(\.isNumber)
        if !contactIsMasked, digits.count >= 3, (phone ?? "").filter(\.isNumber).contains(digits) { return true }
        return false
    }
}

extension LeadRecipient {
    var companyTitle: String {
        if let name = companyName?.nilIfBlank { return name }
        if let slug = companySlug?.nilIfBlank { return slug.replacingOccurrences(of: "-", with: " ").capitalized }
        if let countHint {
            return countHint == 1 ? "1 company" : "\(countHint) companies"
        }
        return "Company"
    }

    static func statusTitle(for status: String) -> String {
        switch status.lowercased() {
        case "accepted": return "Accepted"
        case "offered": return "Offered"
        case "queued": return "Queued"
        case "declined": return "Declined"
        case "delivered": return "Delivered"
        case "late": return "Late"
        case "expired": return "Expired"
        case "released": return "Released"
        case "cancelled": return "Cancelled"
        case "failed": return "Failed"
        case "sent": return "Sent"
        case "pending": return "Pending"
        case "skipped": return "Skipped"
        case "voided": return "Voided"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var statusTitle: String {
        Self.statusTitle(for: displayStatus)
    }

    var statusSymbol: String {
        switch displayStatus {
        case "accepted": return "checkmark.circle.fill"
        case "offered", "sent": return "paperplane.fill"
        case "declined", "failed": return "xmark.circle.fill"
        case "queued", "pending": return "clock.fill"
        case "delivered": return "tray.and.arrow.down.fill"
        case "expired", "late": return "hourglass"
        case "released": return "arrow.uturn.backward"
        case "cancelled", "voided": return "minus.circle"
        case "skipped": return "forward.end"
        default: return "circle.fill"
        }
    }

    var statusColor: Color {
        switch displayStatus {
        case "accepted", "delivered": return Theme.calls
        case "offered", "sent": return Theme.info
        case "queued", "pending", "late": return Theme.warn
        case "declined", "failed": return Theme.bad
        default: return .gray
        }
    }

    var priceLine: String? {
        var parts: [String] = []
        if let priceSek, priceSek > 0 { parts.append(Fmt.sek(priceSek)) }
        if isFree {
            if let freeN, freeN > 0 { parts.append("Free trial \(freeN)") }
            else { parts.append("Free") }
        } else if billable == true {
            parts.append("Billed")
        } else if billable == false {
            parts.append("Not billed")
        }
        if let tier = tier?.nilIfBlank { parts.append("Tier \(tier)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var stampLines: [String] {
        var lines: [String] = []
        func add(_ label: String, _ raw: String?) {
            guard let date = Fmt.parse(raw) else { return }
            lines.append("\(label) · \(Fmt.ago(date))")
        }
        if sendAfter != nil && sendAfter != offeredAt { add("Send", sendAfter) }
        add("Offered", offeredAt)
        add("Viewed", viewedAt)
        add("Accepted", acceptedAt)
        add("Declined", declinedAt)
        add("Delivered", deliveredAt)
        add("Expired", expiredAt)
        add("Released", releasedAt)
        add("Contacted", contactedAt)
        return lines
    }
}
