import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var ns
    @State private var range = 30
    @State private var selection: Date?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    greeting
                    if let msg = store.errorMessage { ErrorBanner(message: msg) }

                    if let s = store.summary {
                        hero(s)
                        tiles(s)
                        chartCard
                        attention(s)
                        topClients
                        latest
                        footer
                    } else if store.isRefreshing || store.errorMessage == nil {
                        DashboardSkeleton()
                    } else {
                        EmptyState(symbol: "wifi.exclamationmark", title: "No data yet",
                                   message: "Pull down to try again when you have a connection.",
                                   actionTitle: "Try Again") { Task { await store.refresh() } }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.smooth, value: store.errorMessage)
            }
            .screenBackground()
            .refreshable { await store.refresh() }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
            }
            .appDestinations(ns)
        }
    }

    private var greeting: some View {
        Text("\(Fmt.greeting()), Anton · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, -6)
    }

    // MARK: Hero

    private func hero(_ s: Summary) -> some View {
        let today = store.leadsToday
        let week = store.leadsInLast(days: 7)
        let prevWeek = store.leadsInLast(days: 7, offset: 1)
        let month = store.leadsInLast(days: 30)
        let prevMonth = store.leadsInLast(days: 30, offset: 1)
        let spark = Analytics.daily(store.realLeads, days: 21).map { Double($0.total) }

        return Button {
            store.selectedTab = .leads
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Leads today", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    DeltaChip(percent: Analytics.percent(today, store.leadsYesterdaySoFar), onDark: true, suffix: "vs yesterday")
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RollingNumber(value: Double(today)) { "\(Int($0.rounded()))" }
                        .font(.rounded(68, .heavy))
                        .foregroundStyle(.white)
                    Text(today == 0 ? "quiet so far" : "so far")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                Sparkline(values: spark, color: .white, lineWidth: 2.5)
                    .frame(height: 56)
                    .padding(.horizontal, -4)
                Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
                HStack(alignment: .top) {
                    heroStat("7 days", week, Analytics.percent(week, prevWeek))
                    heroStat("30 days", month, Analytics.percent(month, prevMonth))
                    heroStat("Missed 7d", s.leads?.missed7 ?? 0, nil)
                }
            }
            .padding(20)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.hero)
                    Circle().fill(.white.opacity(0.10)).frame(width: 220).blur(radius: 40).offset(x: 120, y: -90)
                    Circle().fill(Theme.lilac.opacity(0.25)).frame(width: 180).blur(radius: 50).offset(x: -120, y: 100)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
            .shadow(color: Theme.violet.opacity(0.35), radius: 22, y: 10)
        }
        .buttonStyle(.pressable)
    }

    private func heroStat(_ label: String, _ value: Int, _ pct: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text("\(value)")
                .font(.rounded(22))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            if let pct {
                DeltaChip(percent: pct, onDark: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tiles

    private func tiles(_ s: Summary) -> some View {
        let rev = store.monthlyRevenue.suffix(12)
        let revSpark = rev.map { $0.eur > 0 ? $0.eur : $0.sek }
        let mrr = Fmt.moneyParts(s.mrr?.total)
        let paid = Fmt.moneyParts(s.paid?.thisMonth)
        let unpaid = Fmt.moneyParts(s.invoices?.unpaid)
        let thisM = s.paid?.thisMonth ?? .zero, lastM = s.paid?.lastMonth ?? .zero
        let paidPct = thisM.eur > 0 || lastM.eur > 0 ? Analytics.percent(thisM.eur, lastM.eur) : Analytics.percent(thisM.sek, lastM.sek)
        let calls30 = s.leads?.calls30 ?? 0, missed30 = s.leads?.missed30 ?? 0
        let answered = calls30 > 0 ? Int((Double(max(calls30 - missed30, 0)) / Double(calls30) * 100).rounded()) : 100
        let callSpark = Analytics.daily(store.realLeads, days: 14).map { Double($0.calls) }
        let unpaidClients = store.clients.filter { !($0.unpaid?.isZero ?? true) }.count
        let overdue = s.invoices?.overdueCount ?? 0

        return LazyVGrid(columns: columns, spacing: 12) {
            Button { store.selectedTab = .money } label: {
                MetricTile(title: "MRR", symbol: "arrow.triangle.2.circlepath", tint: Theme.violet,
                           value: mrr.main, extra: mrr.extra,
                           caption: "\(store.payingClients.count) paying clients", spark: Array(revSpark))
            }
            .buttonStyle(.pressable)
            Button { store.selectedTab = .money } label: {
                MetricTile(title: "Paid", symbol: "checkmark.seal.fill", tint: Theme.money,
                           value: paid.main, extra: paid.extra, percent: paidPct,
                           caption: "This month", spark: Array(revSpark))
            }
            .buttonStyle(.pressable)
            Button { store.selectedTab = .money } label: {
                MetricTile(title: "Unpaid", symbol: "hourglass", tint: overdue > 0 ? Theme.bad : Theme.warn,
                           value: unpaid.main, extra: unpaid.extra,
                           caption: overdue > 0 ? "\(overdue) overdue · \(unpaidClients) clients" : "\(unpaidClients) clients owe")
            }
            .buttonStyle(.pressable)
            MetricTile(title: "Calls answered", symbol: "phone.fill", tint: Theme.calls,
                       value: "\(answered)%",
                       caption: "\(missed30) missed of \(calls30) in 30 days", spark: callSpark)
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        let gran: ChartGranularity = range > 31 ? .week : .day
        let data = gran == .day ? Analytics.daily(store.realLeads, days: range) : Analytics.weekly(store.realLeads, weeks: 13)
        let total = data.reduce(0) { $0 + $1.total }
        let selected = selection.flatMap { sel in
            data.first { Calendar.current.isDate($0.day, equalTo: sel, toGranularity: gran == .day ? .day : .weekOfYear) }
        }
        let value = selected?.total ?? total
        let detail: String = {
            if let d = selected {
                let when = gran == .day
                    ? d.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    : "Week of \(d.day.formatted(.dateTime.day().month(.abbreviated)))"
                return "\(when) · \(d.forms) forms, \(d.calls) calls, \(d.missed) missed"
            }
            let avg = Double(total) / Double(max(range, 1))
            return "Last \(range) days · \(avg.formatted(.number.precision(.fractionLength(1)).locale(Fmt.sv))) a day"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ScrubHeader(title: "Leads", value: "\(value)", detail: detail)
                RangePicker(options: [(7, "7D"), (30, "30D"), (90, "90D")], selection: $range)
            }
            LeadsBarChart(data: data, granularity: gran, selection: $selection, height: 190)
            LeadLegend()
        }
        .card()
        .animation(.snappy(duration: 0.2), value: selected?.day)
    }

    // MARK: Attention

    private func attention(_ s: Summary) -> some View {
        let rows = attentionRows(s)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Needs attention")
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    rows[i]
                    if i < rows.count - 1 { Divider().padding(.leading, 60) }
                }
            }
            .card(padding: 4)
        }
    }

    private func attentionRows(_ s: Summary) -> [AnyView] {
        let lines = store.unpaidLines
        let oldest = lines.map(\.days).max() ?? 0
        let overdue = s.invoices?.overdueCount ?? 0
        let drafts = s.approvals?.total ?? 0
        let missed7 = s.leads?.missed7 ?? 0
        let quiet = store.payingClients.filter { ($0.d30 ?? 0) == 0 }
        let unpaid = s.invoices?.unpaid ?? .zero
        let goMoney = { store.selectedTab = .money }

        var rows: [AnyView] = []
        if !unpaid.isZero {
            rows.append(AnyView(AttentionRow(symbol: "banknote.fill", tint: oldest > 60 ? Theme.bad : Theme.warn,
                                             title: "\(Fmt.money(unpaid)) unpaid",
                                             subtitle: "\(lines.count) open items · oldest \(oldest) days", action: goMoney)))
        }
        if overdue > 0 {
            rows.append(AnyView(AttentionRow(symbol: "exclamationmark.triangle.fill", tint: Theme.bad,
                                             title: "\(overdue) overdue \(overdue == 1 ? "invoice" : "invoices")",
                                             subtitle: "Past the due date in Stripe", action: goMoney)))
        }
        if missed7 > 0 {
            let route = LeadFilterRoute(title: "Missed calls", filter: LeadFilter(kind: .missed, days: 7))
            rows.append(AnyView(
                NavigationLink(value: route) {
                    AttentionRowLabel(symbol: "phone.down.fill", tint: Theme.missed,
                                      title: "\(missed7) missed \(missed7 == 1 ? "call" : "calls") this week",
                                      subtitle: "Call them back while they are warm")
                }
                .buttonStyle(.plain)
            ))
        }
        if drafts > 0 {
            rows.append(AnyView(
                Link(destination: APIClient.webAdminURL) {
                    AttentionRowLabel(symbol: "doc.badge.clock.fill", tint: Theme.info,
                                      title: "\(drafts) invoice \(drafts == 1 ? "draft" : "drafts") to review",
                                      subtitle: "Approve them in the web admin", external: true)
                }
                .buttonStyle(.plain)
            ))
        }
        if !quiet.isEmpty {
            rows.append(AnyView(AttentionRow(symbol: "moon.zzz.fill", tint: Theme.deepViolet,
                                             title: "\(quiet.count) paying \(quiet.count == 1 ? "client" : "clients") with no leads",
                                             subtitle: quiet.prefix(3).map(\.displayName).joined(separator: ", "),
                                             action: { store.selectedTab = .clients })))
        }
        if let g = s.gsc, g.stale == true {
            rows.append(AnyView(AttentionRowLabel(symbol: "magnifyingglass", tint: .gray,
                                                  title: "Search Console is \(g.staleDays ?? 0) days behind",
                                                  subtitle: "Reconnect it to see fresh search clicks", chevron: false)))
        }
        if rows.isEmpty {
            rows.append(AnyView(AttentionRowLabel(symbol: "checkmark.seal.fill", tint: Theme.calls,
                                                  title: "All clear", subtitle: "Nothing needs you right now", chevron: false)))
        }
        return rows
    }

    // MARK: Top clients

    private var topClients: some View {
        let top = store.clients.filter { ($0.d30 ?? 0) > 0 }.sorted { ($0.d30 ?? 0) > ($1.d30 ?? 0) }.prefix(10)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top clients", subtitle: "Leads in the last 30 days", actionTitle: "All") { store.selectedTab = .clients }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(top)) { c in
                        NavigationLink(value: c) {
                            TopClientCard(client: c, spark: Analytics.daily(store.leads(forClient: c.clientId), days: 14).map { Double($0.total) })
                                .zoomSource("client-\(c.clientId)", ns)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -16)
        }
    }

    // MARK: Latest

    private var latest: some View {
        let recent = Array(store.realLeads.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Latest leads", actionTitle: "See all") { store.selectedTab = .leads }
            VStack(spacing: 0) {
                if recent.isEmpty {
                    EmptyState(symbol: "tray", title: "No leads yet", message: "New calls and form leads show up here.")
                }
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, lead in
                    NavigationLink(value: lead) {
                        LeadRow(lead: lead, timeStyle: .ago)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .zoomSource("lead-\(lead.id)", ns)
                    .leadContextMenu(lead)
                    if index < recent.count - 1 { Divider().padding(.leading, 70) }
                }
            }
            .card(padding: 4)
        }
    }

    private var footer: some View {
        Group {
            if let d = store.lastUpdated {
                Text("Updated \(Fmt.relative(d))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: Pieces

struct AttentionRowLabel: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    var chevron = true
    var external = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct AttentionRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            AttentionRowLabel(symbol: symbol, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

struct TopClientCard: View {
    var client: Client
    var spark: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Monogram(name: client.displayName, size: 34)
                Spacer()
                if let d7 = client.d7, d7 > 0 {
                    Chip(text: "\(d7) this week", color: Theme.calls)
                }
            }
            Text(client.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(client.d30 ?? 0)")
                    .font(.rounded(28))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("leads").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            MiniBars(values: spark, color: Theme.avatarColors(client.displayName)[0])
                .frame(height: 26)
        }
        .frame(width: 168, alignment: .leading)
        .card(padding: 14)
    }
}

struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.hero)
                .opacity(0.35)
                .frame(height: 290)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonBlock(width: 80, height: 12)
                        SkeletonBlock(width: 110, height: 24)
                        Spacer()
                        SkeletonBlock(width: 60, height: 14, radius: 7)
                    }
                    .frame(height: 100)
                    .card(padding: 14)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 70, height: 12)
                SkeletonBlock(width: 60, height: 28)
                SkeletonBlock(height: 170, radius: 12)
            }
            .card()
        }
        .shimmering()
        .accessibilityLabel("Loading")
    }
}
