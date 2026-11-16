import SwiftUI
import Charts

struct ClientHealth {
    var label: String
    var color: Color
    var symbol: String
    var rank: Int
}

extension Client {
    var isPaying: Bool { (mrr ?? 0) > 0 }

    var health: ClientHealth {
        if (overdueInvoices ?? 0) > 0 { return ClientHealth(label: "Overdue", color: Theme.bad, symbol: "exclamationmark.triangle.fill", rank: 0) }
        if !(unpaid?.isZero ?? true) { return ClientHealth(label: "Owes \(Fmt.money(unpaid))", color: Theme.warn, symbol: "hourglass", rank: 1) }
        let d30 = self.d30 ?? 0, d7 = self.d7 ?? 0
        if isPaying && d30 == 0 { return ClientHealth(label: "No leads", color: Theme.deepViolet, symbol: "moon.zzz.fill", rank: 2) }
        if d30 > 0 && d7 > 0 { return ClientHealth(label: "Healthy", color: Theme.calls, symbol: "checkmark.circle.fill", rank: 4) }
        if d30 > 0 { return ClientHealth(label: "Slow week", color: Theme.info, symbol: "tortoise.fill", rank: 3) }
        return ClientHealth(label: "Inactive", color: .gray, symbol: "pause.circle.fill", rank: 5)
    }
}

enum ClientScope: String, CaseIterable, Identifiable {
    case active, paying, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Active"
        case .paying: return "Paying"
        case .all: return "All"
        }
    }
}

enum ClientSort: String, CaseIterable, Identifiable {
    case leads, mrr, unpaid, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leads: return "Most leads"
        case .mrr: return "Highest MRR"
        case .unpaid: return "Most unpaid"
        case .name: return "Name"
        }
    }
}

struct ClientsView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var ns
    @State private var scope: ClientScope = .active
    @State private var sort: ClientSort = .leads
    @State private var query = ""

    private func list() -> [Client] {
        let q = query.trimmed.lowercased()
        let base = store.clients.filter { c in
            switch scope {
            case .active: if (c.d30 ?? 0) == 0 && !c.isPaying && (c.unpaid?.isZero ?? true) { return false }
            case .paying: if !c.isPaying { return false }
            case .all: break
            }
            if q.isEmpty { return true }
            return [c.name, c.clientId, c.email, c.phone].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
                || (c.sites ?? []).contains { $0.domain.lowercased().contains(q) }
        }
        func unpaidValue(_ c: Client) -> Double { (c.unpaid?.eur ?? 0) * 11 + (c.unpaid?.sek ?? 0) }
        func mrrValue(_ c: Client) -> Double { (c.mrr ?? 0) * ((c.currency ?? "").uppercased() == "EUR" ? 11 : 1) }
        switch sort {
        case .leads: return base.sorted { ($0.d30 ?? 0, mrrValue($0)) > ($1.d30 ?? 0, mrrValue($1)) }
        case .mrr: return base.sorted { mrrValue($0) > mrrValue($1) }
        case .unpaid: return base.sorted { unpaidValue($0) > unpaidValue($1) }
        case .name: return base.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        }
    }

    var body: some View {
        let clients = list()
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let msg = store.errorMessage { ErrorBanner(message: msg) }
                    if store.clients.isEmpty && store.isRefreshing {
                        ForEach(0..<4, id: \.self) { _ in ClientCardSkeleton() }
                    } else {
                        summaryCard
                        Picker("Show", selection: $scope.animation(.smooth)) {
                            ForEach(ClientScope.allCases) { s in Text(s.title).tag(s) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        if clients.isEmpty {
                            if query.isEmpty {
                                EmptyState(symbol: "building.2", title: "No clients here", message: "Try another filter above.")
                            } else {
                                ContentUnavailableView.search(text: query)
                            }
                        }
                        ForEach(clients) { c in
                            NavigationLink(value: c) {
                                ClientCard(client: c,
                                           spark: Analytics.daily(store.leads(forClient: c.clientId), days: 30).map { Double($0.total) },
                                           trend: trend(c))
                                    .zoomSource("client-\(c.clientId)", ns)
                            }
                            .buttonStyle(.pressable)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .refreshable { await store.refresh() }
            .searchable(text: $query, prompt: "Client, email or site")
            .navigationTitle("Clients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort.animation(.smooth)) {
                            ForEach(ClientSort.allCases) { s in Text(s.title).tag(s) }
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

    private func trend(_ c: Client) -> Int? {
        let leads = store.leads(forClient: c.clientId)
        let cal = Calendar.current
        let now = Date()
        guard let a = cal.date(byAdding: .day, value: -30, to: now), let b = cal.date(byAdding: .day, value: -60, to: now) else { return nil }
        return Analytics.percent(Analytics.count(leads, from: a, to: now), Analytics.count(leads, from: b, to: a))
    }

    private var summaryCard: some View {
        let mrr = Fmt.moneyParts(store.summary?.mrr?.total)
        let paying = store.payingClients.count
        let owing = store.clients.filter { !($0.unpaid?.isZero ?? true) }.count
        let active = store.clients.filter { ($0.d30 ?? 0) > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTHLY RECURRING")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(mrr.main)
                        .font(.rounded(36, .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let extra = mrr.extra {
                        Text("+ \(extra)").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer()
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.35))
            }
            HStack(spacing: 0) {
                stat("\(paying)", "Paying")
                stat("\(active)", "With leads")
                stat("\(owing)", "Owe money")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.violet.opacity(0.3), radius: 18, y: 8)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.rounded(22)).monospacedDigit()
            Text(l).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClientCard: View {
    var client: Client
    var spark: [Double]
    var trend: Int?

    var body: some View {
        let health = client.health
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Monogram(name: client.displayName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(client.isPaying ? Fmt.amount(client.mrr, client.currency) : "No fee")
                        .font(.rounded(17, .semibold))
                        .foregroundStyle(client.isPaying ? .primary : .secondary)
                        .monospacedDigit()
                    Text(client.isPaying ? "a month" : client.modelText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(client.d30 ?? 0)")
                            .font(.rounded(26))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("leads · 30d")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Chip(text: health.label, color: health.color, symbol: health.symbol)
                        if let t = trend { DeltaChip(percent: t) }
                    }
                }
                Spacer()
                Sparkline(values: spark, color: Theme.avatarColors(client.displayName)[0], lineWidth: 2)
                    .frame(width: 130, height: 44)
            }
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var subtitle: String {
        var parts = [client.modelText]
        let n = client.sites?.count ?? 0
        if n > 0 { parts.append("\(n) \(n == 1 ? "site" : "sites")") }
        return parts.joined(separator: " · ")
    }
}

struct ClientCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 140, height: 14)
                    SkeletonBlock(width: 90, height: 10)
                }
                Spacer()
            }
            HStack {
                SkeletonBlock(width: 70, height: 26)
                Spacer()
                SkeletonBlock(width: 130, height: 40, radius: 10)
            }
        }
        .card()
        .shimmering()
    }
}

// MARK: Detail

struct ClientDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.zoomNamespace) private var ns
    var clientId: String
    @State private var selection: Date?
    @State private var showAllPayments = false

    var body: some View {
        Group {
            if let c = store.client(clientId) {
                content(c)
            } else {
                EmptyState(symbol: "building.2", title: "Client not found", message: "Pull to refresh on the Clients tab.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ c: Client) -> some View {
        let leads = store.leads(forClient: c.clientId)
        let health = c.health
        return ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 10) {
                    Monogram(name: c.displayName, size: 76)
                        .shadow(color: Theme.avatarColors(c.displayName)[0].opacity(0.4), radius: 14, y: 8)
                    Text(c.displayName)
                        .font(.rounded(26))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Chip(text: c.modelText, color: Theme.violet)
                        Chip(text: health.label, color: health.color, symbol: health.symbol)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    ActionButton(title: "Call", symbol: "phone.fill", tint: Theme.calls, url: Fmt.telURL(c.phone))
                    ActionButton(title: "Email", symbol: "envelope.fill", tint: Theme.info, url: Fmt.mailURL(c.email))
                    ActionButton(title: "Message", symbol: "message.fill", tint: Theme.violet, url: Fmt.smsURL(c.phone))
                }

                kpis(c, leads)
                chart(leads)
                if !(c.payments ?? []).isEmpty { paymentsTimeline(c) }
                if !(c.invoices ?? []).isEmpty { invoices(c) }
                if let sites = c.sites, !sites.isEmpty { sitesCard(sites) }
                latest(c, leads)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground(Theme.avatarColors(c.displayName)[0])
        .navigationTitle(c.displayName)
        .refreshable { await store.refresh() }
    }

    private func kpis(_ c: Client, _ leads: [Lead]) -> some View {
        let now = Date(), cal = Calendar.current
        let a = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let b = cal.date(byAdding: .day, value: -60, to: now) ?? now
        let cur = Analytics.count(leads, from: a, to: now), prev = Analytics.count(leads, from: b, to: a)
        let calls = c.calls30 ?? 0, missed = c.missed30 ?? 0
        let unpaid = Fmt.moneyParts(c.unpaid)
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            MetricTile(title: "MRR", symbol: "arrow.triangle.2.circlepath", tint: Theme.violet,
                       value: c.isPaying ? Fmt.amount(c.mrr, c.currency) : "No fee",
                       caption: c.billingRate.map { "Rate \(Fmt.amount($0, c.currency))" })
            MetricTile(title: "Leads 30d", symbol: "person.crop.rectangle.stack.fill", tint: Theme.forms,
                       value: "\(c.d30 ?? 0)", percent: Analytics.percent(cur, prev),
                       spark: Analytics.daily(leads, days: 30).map { Double($0.total) })
            MetricTile(title: "Calls", symbol: "phone.fill", tint: Theme.calls,
                       value: "\(calls)", caption: missed > 0 ? "\(missed) missed in 30 days" : "None missed")
            MetricTile(title: "Unpaid", symbol: "hourglass", tint: (c.unpaid?.isZero ?? true) ? Theme.calls : Theme.warn,
                       value: (c.unpaid?.isZero ?? true) ? "All paid" : unpaid.main, extra: unpaid.extra,
                       caption: (c.openInvoices ?? 0) > 0 ? "\(c.openInvoices ?? 0) open invoices" : nil)
        }
    }

    private func chart(_ leads: [Lead]) -> some View {
        let data = Analytics.weekly(leads, weeks: 13)
        let total = data.reduce(0) { $0 + $1.total }
        let sel = selection.flatMap { s in data.first { Calendar.current.isDate($0.day, equalTo: s, toGranularity: .weekOfYear) } }
        return VStack(alignment: .leading, spacing: 14) {
            ScrubHeader(title: "Leads per week",
                        value: "\(sel?.total ?? total)",
                        detail: sel.map { "Week of \($0.day.formatted(.dateTime.day().month(.abbreviated))) · \($0.forms) forms, \($0.calls) calls" } ?? "Last 13 weeks")
            LeadsBarChart(data: data, granularity: .week, selection: $selection, height: 170)
            LeadLegend()
        }
        .card()
    }

    private func paymentsTimeline(_ c: Client) -> some View {
        let all = (c.payments ?? []).sorted { ($0.month ?? "") > ($1.month ?? "") }
        let shown = showAllPayments ? all : Array(all.prefix(6))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Payments", systemImage: "calendar").font(.headline)
                Spacer()
                let paid = all.filter { $0.status == "paid" }.count
                Text("\(paid) of \(all.count) paid").font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                    TimelineRow(title: Fmt.shortDate(p.month), amount: Fmt.amount(p.amount, p.currency),
                                status: p.status, isLast: i == shown.count - 1)
                }
            }
            if all.count > 6 {
                Button(showAllPayments ? "Show less" : "Show all \(all.count) months") {
                    withAnimation(.smooth) { showAllPayments.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }

    private func invoices(_ c: Client) -> some View {
        let list = (c.invoices ?? []).sorted { ($0.invoiceDate ?? "") > ($1.invoiceDate ?? "") }.prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Invoices", systemImage: "doc.text.fill").font(.headline)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, inv in
                InvoiceRow(invoice: inv)
                if i < list.count - 1 { Divider() }
            }
        }
        .card()
    }

    private func sitesCard(_ sites: [ClientSite]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sites", systemImage: "globe").font(.headline)
            ForEach(Array(sites.enumerated()), id: \.element.id) { i, s in
                let full = store.site(s.domain)
                NavigationLink(value: full ?? Site(domain: s.domain, name: s.name)) {
                    HStack(spacing: 12) {
                        Monogram(name: s.name ?? s.domain, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name ?? s.domain).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(s.domain).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let full {
                            Text("\(full.d30 ?? 0)")
                                .font(.rounded(17, .semibold))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                            Text("30d").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < sites.count - 1 { Divider().padding(.leading, 46) }
            }
        }
        .card()
    }

    private func latest(_ c: Client, _ leads: [Lead]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Latest leads", systemImage: "tray.full.fill").font(.headline)
                Spacer()
                if !leads.isEmpty {
                    NavigationLink(value: LeadFilterRoute(title: c.displayName, filter: LeadFilter(clientId: c.clientId, days: 90))) {
                        Text("All \(leads.count)").font(.subheadline.weight(.semibold))
                    }
                }
            }
            if leads.isEmpty {
                Text("No leads in the last 90 days").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(Array(leads.prefix(5).enumerated()), id: \.element.id) { i, l in
                NavigationLink(value: l) {
                    LeadRow(lead: l, showClient: false, timeStyle: .ago).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .leadContextMenu(l)
                if i < min(leads.count, 5) - 1 { Divider().padding(.leading, 56) }
            }
        }
        .card()
    }
}

struct TimelineRow: View {
    var title: String
    var amount: String
    var status: String?
    var isLast: Bool

    private var color: Color {
        switch status ?? "" {
        case "paid": return Theme.calls
        case "sent": return Theme.warn
        case "failed": return Theme.bad
        default: return .gray
        }
    }

    private var label: String {
        switch status ?? "" {
        case "paid": return "Paid"
        case "sent": return "Waiting"
        case "failed": return "Failed"
        case "waived": return "Waived"
        case "superseded": return "Replaced"
        case let s: return s.capitalized
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(color.gradient)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2) }
                    .padding(.top, 4)
                if !isLast {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                Chip(text: label, color: color)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct InvoiceRow: View {
    var invoice: Invoice

    var body: some View {
        let status = invoice.status ?? ""
        let color: Color = status == "paid" ? Theme.calls : (invoice.overdue == true ? Theme.bad : (status == "void" || status == "uncollectible" ? .gray : Theme.warn))
        let label = invoice.overdue == true ? "Overdue" : (status == "paid" ? "Paid" : status == "sent" || status == "open" ? "Open" : status.capitalized)
        let row = HStack(spacing: 12) {
            Image(systemName: status == "paid" ? "checkmark.circle.fill" : "doc.text")
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(invoice.number ?? "Invoice").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(Fmt.shortDate(invoice.invoiceDate)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.amount(invoice.amount, invoice.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Chip(text: label, color: color)
            }
        }
        .padding(.vertical, 6)

        if let u = invoice.url, let url = URL(string: u) {
            Link(destination: url) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}
