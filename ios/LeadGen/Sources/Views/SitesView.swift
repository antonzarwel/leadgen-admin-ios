import SwiftUI

enum SiteScope: String, CaseIterable, Identifiable {
    case all, rented, free, personal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .rented: return "Rented"
        case .free: return "Free"
        case .personal: return "Own"
        }
    }
}

struct SitesView: View {
    @Environment(AppStore.self) private var store
    @State private var scope: SiteScope = .all
    @State private var query = ""
    @State private var byLeads = true

    private var sites: [Site] {
        let q = query.trimmed.lowercased()
        let list = store.sites.filter { s in
            (scope == .all || s.siteKind.rawValue == scope.rawValue) &&
            (q.isEmpty || s.domain.lowercased().contains(q) || (s.client ?? "").lowercased().contains(q))
        }
        if byLeads {
            return list.sorted { ($0.d30 ?? 0, $1.domain) > ($1.d30 ?? 0, $0.domain) }
        }
        return list.sorted { $0.domain < $1.domain }
    }

    private func count(_ k: SiteKind) -> Int { store.sites.filter { $0.siteKind == k }.count }

    var body: some View {
        NavigationStack {
            List {
                if store.sites.isEmpty && store.isRefreshing {
                    Section { SkeletonRows(count: 8) }
                } else {
                    Section {
                        HStack(spacing: 0) {
                            stat("\(count(.rented))", "Rented", .green)
                            Divider().frame(height: 32)
                            stat("\(count(.free))", "Free", .orange)
                            Divider().frame(height: 32)
                            stat("\(count(.personal))", "Own", .blue)
                        }
                        .padding(.vertical, 4)
                        Picker("Show", selection: $scope) {
                            ForEach(SiteScope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                    }

                    if sites.isEmpty {
                        Group {
                            if query.isEmpty {
                                ContentUnavailableView("No sites", systemImage: "globe", description: Text(store.errorMessage ?? "Nothing in this group."))
                            } else {
                                ContentUnavailableView.search(text: query)
                            }
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(sites) { s in
                                NavigationLink(value: s) { SiteRow(site: s) }
                            }
                        } footer: {
                            Text("Leads in the last 30 days. Free sites are ready to rent out.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sites")
            .searchable(text: $query, prompt: "Domain or client")
            .refreshable { await store.refresh() }
            .animation(.default, value: scope)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $byLeads) {
                            Text("Most leads").tag(true)
                            Text("Domain").tag(false)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Sort")
                }
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
            }
            .appDestinations()
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SiteRow: View {
    var site: Site

    private var tint: Color {
        switch site.siteKind {
        case .rented: return .green
        case .free: return .orange
        case .personal: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: site.siteKind == .rented ? "house.fill" : site.siteKind == .free ? "tag.fill" : "person.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(site.domain)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(site.client ?? (site.siteKind == .free ? "Free to rent" : "Your own site"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(site.d30 ?? 0)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("leads")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SiteDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    var domain: String

    var body: some View {
        if let site = store.site(domain) {
            content(site)
        } else {
            ContentUnavailableView("Site not found", systemImage: "globe")
        }
    }

    private func content(_ site: Site) -> some View {
        let leads = store.leads.filter { $0.domain == site.domain && !$0.isTestLead }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    SiteRow(site: site)
                    LeadsChart(points: store.daily(days: 30) { $0.domain == site.domain }, height: 130)
                }
                .padding(.vertical, 4)
                LabeledContent("Leads 7 days", value: "\(site.d7 ?? 0)")
                LabeledContent("Leads 30 days", value: "\(site.d30 ?? 0)")
                LabeledContent("Leads 90 days", value: "\(site.d90 ?? 0)")
                if let st = site.status, !st.isEmpty { LabeledContent("Status", value: st.capitalized) }
                if let c = store.client(site.clientId), site.siteKind == .rented {
                    NavigationLink(value: c) { LabeledContent("Client", value: c.displayName) }
                }
                if let url = site.url {
                    Button { openURL(url) } label: { Label("Open website", systemImage: "safari") }
                }
            }

            if let g = site.gsc {
                Section {
                    LabeledContent("Clicks", value: "\(g.clicks ?? 0)")
                    LabeledContent("Impressions", value: "\(g.impressions ?? 0)")
                } header: {
                    Text("Google Search, 7 days")
                } footer: {
                    if let d = g.date { Text("Latest data \(Fmt.shortDate(d))") }
                }
            }

            Section("Latest leads") {
                if leads.isEmpty {
                    Text("No leads in the last 90 days").foregroundStyle(.secondary)
                }
                ForEach(leads.prefix(10)) { lead in
                    NavigationLink(value: lead) { LeadRow(lead: lead) }
                        .leadActions(lead)
                }
                if leads.count > 10 {
                    NavigationLink(value: LeadFilterRoute(title: site.domain, filter: LeadFilter(domain: site.domain, days: 90))) {
                        Text("All \(leads.count) leads")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(site.domain)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }
}
