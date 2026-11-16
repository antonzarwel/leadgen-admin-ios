import SwiftUI
import Charts

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
    var color: Color {
        switch self {
        case .all: return Theme.violet
        case .rented: return Theme.calls
        case .free: return Theme.warn
        case .personal: return Theme.info
        }
    }
    func matches(_ s: Site) -> Bool {
        switch self {
        case .all: return true
        case .rented: return s.siteKind == .rented
        case .free: return s.siteKind == .free
        case .personal: return s.siteKind == .personal
        }
    }
}

extension SiteKind {
    var color: Color {
        switch self {
        case .rented: return Theme.calls
        case .free: return Theme.warn
        case .personal: return Theme.info
        }
    }
}

struct SitesView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var ns
    @State private var scope: SiteScope = .all
    @State private var byLeads = true
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let q = query.trimmed.lowercased()
        let sites = store.sites
            .filter { scope.matches($0) }
            .filter { q.isEmpty || $0.domain.lowercased().contains(q) || ($0.name ?? "").lowercased().contains(q) || ($0.client ?? "").lowercased().contains(q) }
            .sorted { byLeads ? (($0.d30 ?? 0), ($0.d90 ?? 0)) > (($1.d30 ?? 0), ($1.d90 ?? 0)) : $0.domain < $1.domain }

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let msg = store.errorMessage { ErrorBanner(message: msg) }
                    if store.sites.isEmpty && store.isRefreshing {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)).frame(width: 36, height: 36)
                                    SkeletonBlock(width: 110, height: 12)
                                    SkeletonBlock(width: 70, height: 10)
                                    SkeletonBlock(height: 30, radius: 8)
                                }
                                .card(padding: 14)
                            }
                        }
                        .shimmering()
                    } else {
                        overview
                        chips
                        if sites.isEmpty {
                            if q.isEmpty {
                                EmptyState(symbol: "globe", title: "No sites here", message: "Try another filter.")
                            } else {
                                ContentUnavailableView.search(text: query)
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(sites) { s in
                                NavigationLink(value: s) {
                                    SiteTile(site: s, spark: Analytics.daily(store.leads(forDomain: s.domain), days: 30).map { Double($0.total) })
                                        .zoomSource("site-\(s.domain)", ns)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .animation(.smooth, value: scope)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground(Theme.info)
            .refreshable { await store.refresh() }
            .searchable(text: $query, prompt: "Domain, name or client")
            .navigationTitle("Sites")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $byLeads.animation(.smooth)) {
                            Text("Most leads").tag(true)
                            Text("Domain").tag(false)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Sort")
                }
            }
            .appDestinations(ns)
        }
    }

    private var overview: some View {
        let rented = store.sites.filter { $0.siteKind == .rented }.count
        let free = store.sites.filter { $0.siteKind == .free }.count
        let own = store.sites.filter { $0.siteKind == .personal }.count
        let leads30 = store.sites.reduce(0) { $0 + ($1.d30 ?? 0) }
        let withLeads = store.sites.filter { ($0.d30 ?? 0) > 0 }.count
        let parts: [(String, Int, Color)] = [("Rented", rented, Theme.calls), ("Free", free, Theme.warn), ("Own", own, Theme.info)]

        return HStack(spacing: 18) {
            Chart {
                ForEach(parts.indices, id: \.self) { i in
                    SectorMark(angle: .value("Sites", parts[i].1), innerRadius: .ratio(0.64), angularInset: 2.5)
                        .foregroundStyle(parts[i].2.gradient)
                        .cornerRadius(4)
                }
            }
            .frame(width: 118, height: 118)
            .overlay {
                VStack(spacing: 0) {
                    Text("\(store.sites.count)").font(.rounded(28)).monospacedDigit()
                    Text("sites").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Circle().fill(parts[i].2).frame(width: 8, height: 8)
                        Text(parts[i].0).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(parts[i].1)").font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                }
                Divider()
                Text("\(leads30) leads from \(withLeads) sites in 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SiteScope.allCases) { s in
                    FilterChip(title: s.title, count: store.sites.filter { s.matches($0) }.count, isOn: scope == s, color: s.color) {
                        withAnimation(.smooth) { scope = s }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
    }
}

struct SiteTile: View {
    var site: Site
    var spark: [Double]

    var body: some View {
        let kind = site.siteKind
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Monogram(name: site.name ?? site.domain, size: 36)
                Spacer()
                Chip(text: kind.label, color: kind.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name ?? site.domain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(site.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(site.d30 ?? 0)")
                    .font(.rounded(24))
                    .foregroundStyle((site.d30 ?? 0) > 0 ? .primary : .tertiary)
                    .monospacedDigit()
                Text("leads 30d").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if site.status == "building" {
                    Image(systemName: "hammer.fill").font(.caption).foregroundStyle(Theme.warn)
                } else if site.status == "not_refreshed" {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                }
            }
            MiniBars(values: spark, color: kind.color)
                .frame(height: 24)
            Text(site.client.flatMap { $0.hasPrefix("Orphaned") ? nil : $0 } ?? (kind == .free ? "Ready to rent out" : "Yours"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .card(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

struct SiteDetailView: View {
    @Environment(AppStore.self) private var store
    var domain: String
    @State private var selection: Date?

    var body: some View {
        let site = store.site(domain) ?? Site(domain: domain)
        let leads = store.leads(forDomain: domain)
        let data = Analytics.daily(leads, days: 30)
        let sel = selection.flatMap { s in data.first { Calendar.current.isDate($0.day, inSameDayAs: s) } }
        let kind = site.siteKind

        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Monogram(name: site.name ?? site.domain, size: 76)
                        .shadow(color: kind.color.opacity(0.4), radius: 14, y: 8)
                    Text(site.name ?? site.domain)
                        .font(.rounded(26))
                        .multilineTextAlignment(.center)
                    Text(site.domain).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Chip(text: kind.label, color: kind.color)
                        if let s = site.status { Chip(text: s.replacingOccurrences(of: "_", with: " ").capitalized, color: .gray) }
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    ActionButton(title: "Open site", symbol: "safari.fill", tint: Theme.info, url: site.url)
                    if let c = store.client(site.clientId) {
                        NavigationLink(value: c) {
                            VStack(spacing: 6) {
                                Monogram(name: c.displayName, size: 48)
                                Text(c.displayName).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                    }
                }

                HStack(spacing: 10) {
                    stat("7 days", site.d7 ?? 0)
                    stat("30 days", site.d30 ?? 0)
                    stat("90 days", site.d90 ?? 0)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ScrubHeader(title: "Leads per day",
                                value: "\(sel?.total ?? data.reduce(0) { $0 + $1.total })",
                                detail: sel.map { "\($0.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \($0.forms) forms, \($0.calls) calls" } ?? "Last 30 days")
                    LeadsBarChart(data: data, selection: $selection, height: 160)
                    LeadLegend()
                }
                .card()

                if let g = site.gsc, (g.clicks ?? 0) > 0 || (g.impressions ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Google Search", systemImage: "magnifyingglass").font(.headline)
                        HStack {
                            gscStat("Clicks", g.clicks ?? 0)
                            gscStat("Impressions", g.impressions ?? 0)
                            gscStat("CTR", g.impressions.map { $0 > 0 ? Int((Double(g.clicks ?? 0) / Double($0) * 100).rounded()) : 0 } ?? 0, suffix: "%")
                        }
                        if let d = g.date {
                            Text("Latest data \(Fmt.shortDate(d))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card()
                }

                if !leads.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Latest leads", systemImage: "tray.full.fill").font(.headline)
                            Spacer()
                            NavigationLink(value: LeadFilterRoute(title: site.domain, filter: LeadFilter(domain: site.domain, days: 90))) {
                                Text("All \(leads.count)").font(.subheadline.weight(.semibold))
                            }
                        }
                        ForEach(Array(leads.prefix(5).enumerated()), id: \.element.id) { i, l in
                            NavigationLink(value: l) {
                                LeadRow(lead: l, showClient: false, timeStyle: .ago).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < min(leads.count, 5) - 1 { Divider().padding(.leading, 56) }
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground(kind.color)
        .navigationTitle(site.domain)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ v: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(v)").font(.rounded(24)).monospacedDigit()
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func gscStat(_ label: String, _ v: Int, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(v.formatted(.number.locale(Fmt.sv)))\(suffix)").font(.rounded(20)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
