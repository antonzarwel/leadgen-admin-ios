import SwiftUI

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
    @State private var query = ""
    @State private var sort: ClientSort = .leads

    private var clients: [Client] {
        let q = query.trimmed.lowercased()
        let list = store.clients.filter { c in
            q.isEmpty || c.displayName.lowercased().contains(q) || (c.sites ?? []).contains { $0.domain.lowercased().contains(q) }
        }
        switch sort {
        case .leads: return list.sorted { ($0.d30 ?? 0, $1.displayName) > ($1.d30 ?? 0, $0.displayName) }
        case .mrr: return list.sorted { sekValue($0) > sekValue($1) }
        case .unpaid: return list.sorted { unpaidValue($0) > unpaidValue($1) }
        case .name: return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    // Rough EUR to SEK only for ordering the list, never shown.
    private func sekValue(_ c: Client) -> Double {
        (c.mrr ?? 0) * ((c.currency ?? "").uppercased() == "EUR" ? 11.5 : 1)
    }
    private func unpaidValue(_ c: Client) -> Double {
        (c.unpaid?.sek ?? 0) + (c.unpaid?.eur ?? 0) * 11.5
    }

    var body: some View {
        NavigationStack {
            List {
                if store.clients.isEmpty && store.isRefreshing {
                    Section { SkeletonRows(count: 6) }
                } else if clients.isEmpty {
                    Group {
                        if query.isEmpty {
                            ContentUnavailableView("No clients", systemImage: "person.2", description: Text(store.errorMessage ?? "Pull down to refresh."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    if query.isEmpty, let mrr = store.summary?.mrr {
                        Section {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MRR").font(.subheadline).foregroundStyle(.secondary)
                                    Text(Fmt.money(mrr.total)).font(.title3.bold()).monospacedDigit()
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Active clients").font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(mrr.activeClients ?? store.clients.count)").font(.title3.bold()).monospacedDigit()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section {
                        ForEach(clients) { c in
                            NavigationLink(value: c) { ClientRow(client: c) }
                        }
                    } footer: {
                        Text("Leads count the last 30 days. Per lead MRR is a run rate from the last 30 days.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clients")
            .searchable(text: $query, prompt: "Client or site")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(ClientSort.allCases) { Text($0.title).tag($0) }
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
}

struct ClientRow: View {
    var client: Client

    var body: some View {
        HStack(spacing: 12) {
            Monogram(text: client.displayName)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(client.d30 ?? 0) leads")
                        .monospacedDigit()
                    if (client.missed30 ?? 0) > 0 {
                        Text("· \(client.missed30 ?? 0) missed")
                            .foregroundStyle(.red)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(client.mrrText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle((client.mrr ?? 0) > 0 ? Color.primary : Color.secondary)
                if let u = client.unpaid, !u.isZero {
                    Pill(text: "\(Fmt.money(u)) unpaid", color: (client.overdueInvoices ?? 0) > 0 ? .red : .orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct Monogram: View {
    var text: String
    var size: CGFloat = 38

    private var initials: String {
        let words = text.split(separator: " ").prefix(2)
        let s = words.compactMap { w in w.first.map { String($0) } }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan, .mint, .brown]
        let h = text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[h % palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ClientDetailView: View {
    @Environment(AppStore.self) private var store
    var clientId: String

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        if let c = store.client(clientId) {
            content(c)
        } else {
            ContentUnavailableView("Client not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func content(_ c: Client) -> some View {
        let leads = store.leads.filter { $0.clientId == c.clientId && !$0.isTestLead }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Monogram(text: c.displayName, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.displayName).font(.title2.bold()).lineLimit(2)
                            Text(billingText(c))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        mini("MRR", c.mrrText, "arrow.triangle.2.circlepath", .green)
                        mini("Unpaid", Fmt.money(c.unpaid), "exclamationmark.circle.fill", (c.overdueInvoices ?? 0) > 0 ? .red : .orange)
                        mini("Leads 7 days", "\(c.d7 ?? 0)", "tray.full.fill", .blue)
                        mini("Leads 30 days", "\(c.d30 ?? 0)", "chart.bar.fill", .indigo)
                    }
                    LeadsChart(points: store.daily(days: 30) { $0.clientId == c.clientId }, height: 140)
                }
                .padding(.vertical, 6)
            }

            if c.email != nil || c.phone != nil {
                Section("Contact") {
                    if let p = c.phone, !p.isEmpty, let url = Fmt.telURL(p) {
                        Link(destination: url) { LabeledContent { Text(p).monospacedDigit() } label: { Label("Phone", systemImage: "phone") } }
                    }
                    if let e = c.email, !e.isEmpty, let url = Fmt.mailURL(e.split(separator: ",").first.map { String($0) }) {
                        Link(destination: url) { LabeledContent { Text(e).lineLimit(1).truncationMode(.middle) } label: { Label("Email", systemImage: "envelope") } }
                    }
                }
            }

            Section {
                if leads.isEmpty {
                    Text("No leads in the last 90 days").foregroundStyle(.secondary)
                }
                ForEach(leads.prefix(5)) { lead in
                    NavigationLink(value: lead) { LeadRow(lead: lead, showClient: false) }
                        .leadActions(lead)
                }
                if leads.count > 5 {
                    NavigationLink(value: LeadFilterRoute(title: c.displayName, filter: LeadFilter(clientId: c.clientId, days: 90))) {
                        Text("All \(leads.count) leads")
                    }
                }
            } header: {
                Text("Latest leads")
            }

            if let sites = c.sites, !sites.isEmpty {
                Section("Sites") {
                    ForEach(sites) { s in
                        if let site = store.site(s.domain) {
                            NavigationLink(value: site) { SiteRowSimple(domain: s.domain, leads30: site.d30 ?? 0) }
                        } else {
                            SiteRowSimple(domain: s.domain, leads30: nil)
                        }
                    }
                }
            }

            if let inv = c.invoices, !inv.isEmpty {
                Section("Invoices") {
                    ForEach(inv) { InvoiceRow(invoice: $0) }
                }
            }

            if let pay = c.payments, !pay.isEmpty {
                Section("Payment history") {
                    ForEach(pay) { p in
                        HStack {
                            Text(Fmt.shortDate(p.month))
                            Spacer()
                            Text(Fmt.amount(p.amount, p.currency)).monospacedDigit()
                            PaymentStatus(status: p.status)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(c.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }

    private func billingText(_ c: Client) -> String {
        let rate = c.billingRate ?? 0
        guard rate > 0 else { return c.modelText }
        let amount = Fmt.amount(rate, c.currency)
        if c.billingModel == "per_lead" { return "\(c.modelText), \(amount) per lead" }
        if c.billingModel == "fixed_monthly" { return "\(c.modelText), \(amount)" }
        return c.modelText
    }

    private func mini(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SiteRowSimple: View {
    var domain: String
    var leads30: Int?

    var body: some View {
        HStack {
            Label(domain, systemImage: "globe")
                .lineLimit(1)
            Spacer()
            if let leads30 {
                Text("\(leads30)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InvoiceRow: View {
    var invoice: Invoice
    @Environment(\.openURL) private var openURL

    var body: some View {
        let row = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number ?? "Invoice")
                    .font(.body)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.amount(invoice.amount, invoice.currency))
                .monospacedDigit()
            PaymentStatus(status: invoice.overdue == true ? "overdue" : invoice.status)
        }
        if let s = invoice.url, let url = URL(string: s) {
            Button { openURL(url) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var dateText: String {
        if invoice.status == "paid", let p = invoice.paidAt { return "Paid \(Fmt.shortDate(String(p.prefix(10))))" }
        if let d = invoice.dueDate { return "Due \(Fmt.shortDate(d))" }
        return Fmt.shortDate(invoice.invoiceDate)
    }
}

struct PaymentStatus: View {
    var status: String?

    var body: some View {
        switch status ?? "" {
        case "paid": Pill(text: "Paid", color: .green)
        case "overdue": Pill(text: "Overdue", color: .red)
        case "sent", "open": Pill(text: "Open", color: .orange)
        case "draft": Pill(text: "Draft", color: .gray)
        case "void": Pill(text: "Void", color: .gray)
        case "": EmptyView()
        default: Pill(text: (status ?? "").capitalized, color: .gray)
        }
    }
}
