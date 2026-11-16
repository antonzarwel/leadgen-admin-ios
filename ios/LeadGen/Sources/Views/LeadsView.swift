import SwiftUI

enum KindFilter: String, CaseIterable, Identifiable, Hashable {
    case all, forms, calls, missed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All types"
        case .forms: return "Forms"
        case .calls: return "Calls"
        case .missed: return "Missed calls"
        }
    }
    func matches(_ k: LeadKind) -> Bool {
        switch self {
        case .all: return true
        case .forms: return k == .form || k == .phone
        case .calls: return k.isCall
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

    func matches(_ l: Lead, now: Date = Date()) -> Bool {
        if !showTests && l.isTestLead { return false }
        if let clientId, l.clientId != clientId { return false }
        if let domain, l.domain != domain { return false }
        if !kind.matches(l.leadKind) { return false }
        if let d = l.date, now.timeIntervalSince(d) > Double(days) * 86_400 { return false }
        return true
    }
}

struct LeadsTab: View {
    var body: some View {
        NavigationStack {
            LeadsListView(filter: LeadFilter(), title: "Leads", isRoot: true)
                .appDestinations()
        }
    }
}

struct LeadsListView: View {
    @Environment(AppStore.self) private var store
    @State var filter: LeadFilter
    var title: String
    var isRoot = false
    @State private var query = ""

    private var filtered: [Lead] {
        let q = query.trimmed.lowercased()
        return store.leads.filter { l in
            guard filter.matches(l) else { return false }
            guard !q.isEmpty else { return true }
            let hay = [l.name, l.phone, l.email, l.client, l.domain, l.message, l.notes]
                .compactMap { $0?.lowercased() }
            return hay.contains { $0.contains(q) }
        }
    }

    private var sections: [DaySection] {
        let cal = Calendar.current
        var map: [Date: [Lead]] = [:]
        for l in filtered {
            let day = cal.startOfDay(for: l.date ?? .distantPast)
            map[day, default: []].append(l)
        }
        return map.keys.sorted(by: >).map { DaySection(day: $0, leads: map[$0] ?? []) }
    }

    var body: some View {
        let sections = self.sections
        let count = sections.reduce(0) { $0 + $1.leads.count }
        List {
            if store.leads.isEmpty && store.isRefreshing {
                Section { SkeletonRows() }
            } else if sections.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    summaryRow(count: count)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.leads) { lead in
                            NavigationLink(value: lead) {
                                LeadRow(lead: lead, showClient: filter.clientId == nil)
                            }
                            .leadActions(lead)
                        }
                    } header: {
                        Text(header(for: section.day))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        .animation(.default, value: filter)
    }

    private func summaryRow(count: Int) -> some View {
        let calls = filtered.filter { $0.leadKind.isCall }.count
        let missed = filtered.filter { $0.leadKind == .missed }.count
        return HStack(spacing: 0) {
            stat("\(count)", "Leads")
            Divider().frame(height: 32)
            stat("\(count - calls)", "Forms")
            Divider().frame(height: 32)
            stat("\(calls)", "Calls")
            Divider().frame(height: 32)
            stat("\(missed)", "Missed", tint: missed > 0 ? .red : .primary)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if let msg = store.errorMessage, store.leads.isEmpty {
            ContentUnavailableView("Could not load leads", systemImage: "wifi.exclamationmark", description: Text(msg))
        } else {
            ContentUnavailableView {
                Label("No leads", systemImage: "tray")
            } description: {
                Text("Nothing matches in the last \(filter.days) days.")
            } actions: {
                if filter.isNarrowed {
                    Button("Clear Filters") { filter = LeadFilter(clientId: isRoot ? nil : filter.clientId, domain: isRoot ? nil : filter.domain) }
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Period", selection: $filter.days) {
                Text("Last 7 days").tag(7)
                Text("Last 30 days").tag(30)
                Text("Last 90 days").tag(90)
            }
            Picker("Type", selection: $filter.kind) {
                ForEach(KindFilter.allCases) { k in Text(k.title).tag(k) }
            }
            if isRoot {
                Picker("Client", selection: $filter.clientId) {
                    Text("All clients").tag(String?.none)
                    ForEach(store.clients) { c in
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
            Image(systemName: filter.isNarrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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

/// Call, text and email are safe to offer: they only open the phone or mail app.
struct LeadActions: ViewModifier {
    var lead: Lead
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let url = Fmt.telURL(lead.phone) {
                    Button { openURL(url) } label: { Label("Call", systemImage: "phone.fill") }
                        .tint(.green)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let url = Fmt.mailURL(lead.email) {
                    Button { openURL(url) } label: { Label("Email", systemImage: "envelope.fill") }
                        .tint(.blue)
                }
                if let url = Fmt.smsURL(lead.phone) {
                    Button { openURL(url) } label: { Label("Message", systemImage: "message.fill") }
                        .tint(.indigo)
                }
            }
            .contextMenu {
                if let url = Fmt.telURL(lead.phone) {
                    Button { openURL(url) } label: { Label("Call", systemImage: "phone") }
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
}

struct LeadDetailView: View {
    @Environment(AppStore.self) private var store
    var lead: Lead
    @State private var copied = 0

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    KindIcon(kind: lead.leadKind, size: 64)
                    Text(lead.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        StatusBadge(status: lead.status)
                        Pill(text: lead.leadKind.label, color: .secondary)
                        if lead.isTestLead { Pill(text: "Test", color: .orange) }
                    }
                    if let d = lead.date {
                        Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    actionButtons
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if lead.phone != nil || lead.email != nil {
                Section("Contact") {
                    if let p = lead.phone, !p.isEmpty, let url = Fmt.telURL(p) {
                        Link(destination: url) {
                            LabeledContent { Text(p).monospacedDigit() } label: { Label("Phone", systemImage: "phone") }
                        }
                        .contextMenu { Button { copy(p) } label: { Label("Copy Number", systemImage: "doc.on.doc") } }
                    }
                    if let e = lead.email, !e.isEmpty, let url = Fmt.mailURL(e) {
                        Link(destination: url) {
                            LabeledContent { Text(e).lineLimit(1).truncationMode(.middle) } label: { Label("Email", systemImage: "envelope") }
                        }
                        .contextMenu { Button { copy(e) } label: { Label("Copy Email", systemImage: "doc.on.doc") } }
                    }
                }
            }

            if let m = lead.message?.trimmed, !m.isEmpty {
                Section("Message") {
                    Text(m).textSelection(.enabled)
                }
            }

            Section("Details") {
                if let c = store.client(lead.clientId) {
                    NavigationLink(value: c) { LabeledContent("Client", value: c.displayName) }
                } else if let c = lead.client {
                    LabeledContent("Client", value: c)
                }
                if let d = lead.domain {
                    if let site = store.site(d) {
                        NavigationLink(value: site) { LabeledContent("Site", value: d) }
                    } else {
                        LabeledContent("Site", value: d)
                    }
                }
                LabeledContent("Source", value: sourceLabel)
                if let dur = Fmt.duration(lead.durationS) { LabeledContent("Call length", value: dur) }
                if let f = lead.followUpDate { LabeledContent("Follow up", value: Fmt.shortDate(f)) }
                if let v = lead.wonValueSek, v > 0 { LabeledContent("Won value", value: Fmt.sek(v)) }
            }

            if let n = lead.notes?.trimmed, !n.isEmpty {
                Section("Notes") {
                    Text(n).textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(lead.leadKind.label)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
    }

    private var sourceLabel: String {
        switch lead.source ?? "" {
        case "telavox": return "Phone call (Telavox)"
        case "typeform": return "Website form (Typeform)"
        case "jotform": return "Website form (Jotform)"
        case "phone": return "Added by hand"
        case "": return "Unknown"
        case let s: return s.capitalized
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            actionButton("Call", "phone.fill", Fmt.telURL(lead.phone))
            actionButton("Message", "message.fill", Fmt.smsURL(lead.phone))
            actionButton("Email", "envelope.fill", Fmt.mailURL(lead.email))
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, _ symbol: String, _ url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                VStack(spacing: 4) {
                    Image(systemName: symbol).font(.title3)
                    Text(title).font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.tertiary)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
        }
    }

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        copied += 1
    }
}
