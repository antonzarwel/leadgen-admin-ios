import SwiftUI
import MapKit

enum KindFilter: String, CaseIterable, Identifiable, Hashable {
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
    var color: Color {
        switch self {
        case .all: return Theme.violet
        case .forms: return Theme.forms
        case .calls: return Theme.calls
        case .missed: return Theme.missed
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

struct LeadFilter: Hashable {
    var clientId: String?
    var domain: String?
    var kind: KindFilter = .all
    var days = 30
    var showTests = false

    var isNarrowed: Bool { clientId != nil || domain != nil || kind != .all || days != 30 || showTests }

    func matchesExceptKind(_ l: Lead, now: Date = Date()) -> Bool {
        if !showTests && l.isTestLead { return false }
        if let clientId, l.clientId != clientId { return false }
        if let domain, l.domain != domain { return false }
        if let d = l.date, now.timeIntervalSince(d) > Double(days) * 86_400 { return false }
        return true
    }

    func matches(_ l: Lead, now: Date = Date()) -> Bool {
        matchesExceptKind(l, now: now) && kind.matches(l.leadKind)
    }
}

struct LeadsTab: View {
    @Namespace private var ns

    var body: some View {
        NavigationStack {
            LeadsListView(filter: LeadFilter(), title: "Leads", isRoot: true)
                .appDestinations(ns)
        }
    }
}

struct LeadsListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.zoomNamespace) private var ns
    @State var filter: LeadFilter
    var title: String
    var isRoot = false
    @State private var query = ""

    private var base: [Lead] {
        let q = query.trimmed.lowercased()
        return store.leads.filter { l in
            guard filter.matchesExceptKind(l) else { return false }
            guard !q.isEmpty else { return true }
            let hay = [l.name, l.phone, l.email, l.client, l.domain, l.message, l.notes]
                .compactMap { $0?.lowercased() }
            return hay.contains { $0.contains(q) }
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func sections(_ leads: [Lead]) -> [DaySection] {
        let cal = Calendar.current
        var map: [Date: [Lead]] = [:]
        for l in leads {
            map[cal.startOfDay(for: l.date ?? .distantPast), default: []].append(l)
        }
        return map.keys.sorted(by: >).map { DaySection(day: $0, leads: map[$0] ?? []) }
    }

    var body: some View {
        let base = self.base
        let shown = base.filter { filter.kind.matches($0.leadKind) }
        let sections = self.sections(shown)

        List {
            if store.leads.isEmpty && store.isRefreshing {
                Section { SkeletonRows(count: 7).padding(.vertical, 6) }
            } else if sections.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    LeadsSummaryStrip(leads: shown, days: filter.days)
                        .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.leads) { lead in
                            NavigationLink(value: lead) {
                                LeadRow(lead: lead, showClient: filter.clientId == nil)
                            }
                            .zoomSource("lead-\(lead.id)", ns)
                            .leadActions(lead)
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
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) { chipBar(base) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Name, phone, email or site")
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            if isRoot {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
            }
        }
        .animation(.smooth(duration: 0.3), value: filter)
    }

    private func chipBar(_ base: [Lead]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KindFilter.allCases) { k in
                    FilterChip(title: k.title, count: base.filter { k.matches($0.leadKind) }.count,
                               isOn: filter.kind == k, color: k.color) {
                        filter.kind = k
                    }
                }
                Divider().frame(height: 22).padding(.horizontal, 2)
                Menu {
                    Picker("Period", selection: $filter.days) {
                        Text("Last 7 days").tag(7)
                        Text("Last 30 days").tag(30)
                        Text("Last 90 days").tag(90)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("\(filter.days) days")
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if let msg = store.errorMessage, store.leads.isEmpty {
            EmptyState(symbol: "wifi.exclamationmark", title: "Could not load leads", message: msg, tint: Theme.warn,
                       actionTitle: "Try Again") { Task { await store.refresh() } }
        } else {
            EmptyState(symbol: "tray", title: "No leads here",
                       message: "Nothing matches in the last \(filter.days) days.",
                       actionTitle: filter.kind != .all || filter.days != 90 ? "Show all of the last 90 days" : nil) {
                filter.kind = .all
                filter.days = 90
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            if isRoot {
                Picker("Client", selection: $filter.clientId) {
                    Text("All clients").tag(String?.none)
                    ForEach(store.clients.filter { ($0.d30 ?? 0) > 0 || $0.clientId == filter.clientId }) { c in
                        Text(c.displayName).tag(Optional(c.clientId))
                    }
                }
                .pickerStyle(.menu)
            }
            Toggle("Show test leads", isOn: $filter.showTests)
            if filter.isNarrowed && isRoot {
                Divider()
                Button("Clear Filters", role: .destructive) { filter = LeadFilter() }
            }
        } label: {
            Image(systemName: filter.clientId != nil || filter.showTests ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
    }

    private func header(for day: Date) -> String {
        let cal = Calendar.current
        if day == .distantPast { return "No date" }
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct LeadsSummaryStrip: View {
    var leads: [Lead]
    var days: Int

    var body: some View {
        let forms = leads.filter { $0.leadKind == .form || $0.leadKind == .phone }.count
        let calls = leads.filter { $0.leadKind == .call }.count
        let missed = leads.filter { $0.leadKind == .missed }.count
        let total = max(leads.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(leads.count)")
                    .font(.rounded(34))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(leads.count)))
                Text("leads in \(days) days")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    seg(forms, total, geo.size.width, Theme.forms)
                    seg(calls, total, geo.size.width, Theme.calls)
                    seg(missed, total, geo.size.width, Theme.missed)
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                legend("Forms", forms, Theme.forms)
                legend("Calls", calls, Theme.calls)
                legend("Missed", missed, Theme.missed)
            }
        }
    }

    @ViewBuilder
    private func seg(_ n: Int, _ total: Int, _ width: CGFloat, _ c: Color) -> some View {
        if n > 0 {
            Capsule().fill(c.gradient).frame(width: max(6, (width - 6) * CGFloat(n) / CGFloat(total)))
        }
    }

    private func legend(_ t: String, _ n: Int, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).foregroundStyle(.secondary)
            Text("\(n)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
    }
}

/// Call, text and email only open the phone or mail app.
struct LeadActions: ViewModifier {
    var lead: Lead
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
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

struct LeadContextMenu: ViewModifier {
    var lead: Lead
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.contextMenu {
            if let url = Fmt.telURL(lead.phone) {
                Button { openURL(url) } label: { Label("Call", systemImage: "phone") }
            }
            if let url = Fmt.smsURL(lead.phone) {
                Button { openURL(url) } label: { Label("Message", systemImage: "message") }
            }
            if let url = Fmt.mailURL(lead.email) {
                Button { openURL(url) } label: { Label("Email", systemImage: "envelope") }
            }
            if let p = lead.phone, !p.isEmpty {
                Button { UIPasteboard.general.string = p } label: { Label("Copy Number", systemImage: "doc.on.doc") }
            }
            if let e = lead.email, !e.isEmpty {
                Button { UIPasteboard.general.string = e } label: { Label("Copy Email", systemImage: "doc.on.doc") }
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

// MARK: Lead detail

struct LeadDetailView: View {
    @Environment(AppStore.self) private var store
    var lead: Lead
    @State private var copied = 0
    @State private var place: LeadPlace?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                actionRow
                if let place { MapCard(place: place) }
                if let m = lead.message?.trimmed, !m.isEmpty { messageCard(m) }
                contactCard
                detailsCard
                if let n = lead.notes?.trimmed, !n.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text").font(.headline)
                        Text(n).textSelection(.enabled)
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground(Theme.tint(for: lead.leadKind))
        .navigationTitle(lead.leadKind.label)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
        .task {
            let p = await LeadPlace.resolve(for: lead, site: store.site(lead.domain))
            withAnimation(.smooth) { place = p }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            LeadAvatar(lead: lead, size: 84)
                .shadow(color: Theme.tint(for: lead.leadKind).opacity(0.35), radius: 16, y: 8)
            Text(lead.title)
                .font(.rounded(26))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Chip(text: kindText, color: Theme.tint(for: lead.leadKind), symbol: lead.leadKind.symbol)
                StatusChip(status: lead.status)
                if lead.isTestLead { Chip(text: "Test", color: Theme.warn) }
            }
            if let d = lead.date {
                Text("\(d.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())) · \(Fmt.relative(d))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var kindText: String {
        if lead.leadKind == .call, let d = Fmt.duration(lead.durationS) { return "Call \(d)" }
        return lead.leadKind.label
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Call", symbol: "phone.fill", tint: Theme.calls, url: Fmt.telURL(lead.phone))
            ActionButton(title: "Message", symbol: "message.fill", tint: Theme.violet, url: Fmt.smsURL(lead.phone))
            ActionButton(title: "Email", symbol: "envelope.fill", tint: Theme.info, url: Fmt.mailURL(lead.email))
            ActionButton(title: "Site", symbol: "safari.fill", tint: .gray, url: lead.domain.flatMap { URL(string: "https://\($0)") })
        }
    }

    private func messageCard(_ m: String) -> some View {
        let lines = m.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let fields = lines.compactMap { line -> (String, String)? in
            guard let r = line.range(of: ": ") else { return nil }
            let k = String(line[..<r.lowerBound]).trimmed, v = String(line[r.upperBound...]).trimmed
            guard !k.isEmpty, k.count < 30, !v.isEmpty else { return nil }
            return (k, v)
        }
        let free = lines.filter { l in !fields.contains { l.hasPrefix($0.0 + ":") } }.joined(separator: "\n").trimmed

        return VStack(alignment: .leading, spacing: 12) {
            Label("Message", systemImage: "text.bubble.fill")
                .font(.headline)
                .foregroundStyle(Theme.tint(for: lead.leadKind))
            if !free.isEmpty {
                Text(free)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.tint(for: lead.leadKind).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !fields.isEmpty {
                VStack(spacing: 0) {
                    ForEach(fields.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fields[i].0).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(fields[i].1).fontWeight(.medium).multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 9)
                        if i < fields.count - 1 { Divider() }
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var contactCard: some View {
        let phone = lead.phone?.trimmed ?? ""
        let email = lead.email?.trimmed ?? ""
        if !phone.isEmpty || !email.isEmpty {
            VStack(spacing: 0) {
                if !phone.isEmpty {
                    contactRow(symbol: "phone.fill", tint: Theme.calls, label: "Phone", value: Fmt.phone(phone), url: Fmt.telURL(phone), copy: phone)
                }
                if !phone.isEmpty && !email.isEmpty { Divider().padding(.leading, 52) }
                if !email.isEmpty {
                    contactRow(symbol: "envelope.fill", tint: Theme.info, label: "Email", value: email, url: Fmt.mailURL(email), copy: email)
                }
            }
            .card(padding: 4)
        }
    }

    private func contactRow(symbol: String, tint: Color, label: String, value: String, url: URL?, copy: String) -> some View {
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
                    Text(value).font(.body.weight(.medium)).lineLimit(1)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if let c = store.client(lead.clientId) {
                NavigationLink(value: c) {
                    detailRow("Client", c.displayName, symbol: "building.2.fill", link: true)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            } else if let c = lead.client {
                detailRow("Client", lead.clientId == "orphaned" ? "No client yet" : c, symbol: "building.2.fill")
                Divider().padding(.leading, 16)
            }
            if let d = lead.domain {
                if let site = store.site(d) {
                    NavigationLink(value: site) { detailRow("Site", d, symbol: "globe", link: true) }
                        .buttonStyle(.plain)
                } else {
                    detailRow("Site", d, symbol: "globe")
                }
                Divider().padding(.leading, 16)
            }
            detailRow("Source", Fmt.sourceLabel(lead.source), symbol: "arrow.down.forward.circle")
            if let dur = Fmt.duration(lead.durationS) {
                Divider().padding(.leading, 16)
                detailRow("Call length", dur, symbol: "timer")
            }
            if let f = lead.followUpDate {
                Divider().padding(.leading, 16)
                detailRow("Follow up", Fmt.shortDate(f), symbol: "calendar.badge.clock")
            }
            if let v = lead.wonValueSek, v > 0 {
                Divider().padding(.leading, 16)
                detailRow("Won value", Fmt.sek(v), symbol: "trophy.fill")
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

    /// Finds a town from the form ("Kommun: Norrköping") or the site name ("VVS Ängelholm").
    static func guessName(for lead: Lead, site: Site?) -> String? {
        for line in (lead.message ?? "").split(separator: "\n") {
            let l = line.lowercased()
            for key in ["kommun:", "ort:", "stad:", "postort:", "adress:", "address:"] where l.hasPrefix(key) {
                let v = String(line.dropFirst(key.count)).trimmed
                if !v.isEmpty { return v }
            }
        }
        if let n = site?.name?.trimmed, let last = n.split(separator: " ").last, last.count > 2, last.first?.isUppercase == true {
            return String(last)
        }
        return nil
    }

    static func resolve(for lead: Lead, site: Site?) async -> LeadPlace? {
        guard let name = guessName(for: lead, site: site) else { return nil }
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
