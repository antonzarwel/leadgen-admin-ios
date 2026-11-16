import SwiftUI
import Charts

struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var ns
    @State private var currency: Currency = .eur
    @State private var months = 12
    @State private var selection: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let msg = store.errorMessage { ErrorBanner(message: msg) }
                    if let s = store.summary {
                        hero(s)
                        revenueCard
                        mrrMix(s)
                        aging
                        owing
                        openInvoices(s)
                    } else if store.isRefreshing || store.errorMessage == nil {
                        DashboardSkeleton()
                    } else {
                        EmptyState(symbol: "creditcard", title: "No money data yet", message: "Pull down to try again.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .screenBackground(Theme.money)
            .refreshable { await store.refresh() }
            .navigationTitle("Money")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountMenu() }
            }
            .appDestinations(ns)
        }
    }

    // MARK: Hero

    private func hero(_ s: Summary) -> some View {
        let thisM = s.paid?.thisMonth ?? .zero, lastM = s.paid?.lastMonth ?? .zero
        let parts = Fmt.moneyParts(thisM)
        let pct = thisM.eur > 0 || lastM.eur > 0 ? Analytics.percent(thisM.eur, lastM.eur) : Analytics.percent(thisM.sek, lastM.sek)
        let monthName = Fmt.parse(s.paid?.thisMonthKey)?.formatted(.dateTime.month(.wide)) ?? "This month"
        let spark = store.monthlyRevenue.suffix(12).map { $0.eur }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Paid in \(monthName)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                DeltaChip(percent: pct, onDark: true, suffix: "vs last month")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(parts.main)
                    .font(.rounded(52, .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let extra = parts.extra {
                    Text("+ \(extra)").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
            Sparkline(values: spark, color: .white, lineWidth: 2.5)
                .frame(height: 50)
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
            HStack(alignment: .top) {
                heroStat("MRR", Fmt.moneyParts(s.mrr?.total))
                heroStat("Last month", Fmt.moneyParts(lastM))
                heroStat("Unpaid", Fmt.moneyParts(s.invoices?.unpaid))
            }
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.moneyHero)
                Circle().fill(.white.opacity(0.10)).frame(width: 220).blur(radius: 40).offset(x: 120, y: -90)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
        .shadow(color: Theme.money.opacity(0.35), radius: 22, y: 10)
    }

    private func heroStat(_ label: String, _ v: (main: String, extra: String?)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
            Text(v.main).font(.rounded(17)).foregroundStyle(.white).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let e = v.extra {
                Text("+ \(e)").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Revenue chart

    private var revenueCard: some View {
        let all = store.monthlyRevenue
        let data = Array(all.suffix(months))
        let values = data.map { $0.value(currency) }
        let total = values.reduce(0, +)
        let avg = values.isEmpty ? 0 : total / Double(values.count)
        let sel = selection.flatMap { s in data.first { Calendar.current.isDate($0.month, equalTo: s, toGranularity: .month) } }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ScrubHeader(title: "Revenue paid",
                            value: currency.format(sel?.value(currency) ?? total),
                            detail: sel.map { $0.month.formatted(.dateTime.month(.wide).year()) }
                                ?? "Last \(data.count) months · avg \(currency.format(avg))")
                VStack(alignment: .trailing, spacing: 8) {
                    RangePicker(options: [(Currency.eur, "EUR"), (Currency.sek, "SEK")], selection: $currency)
                    RangePicker(options: [(6, "6M"), (12, "1Y"), (36, "All")], selection: $months)
                }
            }
            Chart {
                ForEach(data) { m in
                    let on = sel == nil || sel?.id == m.id
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Paid", m.value(currency)))
                        .foregroundStyle(LinearGradient(colors: [Theme.money, Theme.money.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(5)
                        .opacity(on ? 1 : 0.3)
                }
                if avg > 0 && sel == nil {
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true).foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Color.secondary.opacity(0.4))
                    AxisValueLabel().foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 200)
            .sensoryFeedback(.selection, trigger: sel?.id)
        }
        .card()
        .animation(.snappy(duration: 0.2), value: sel?.id)
    }

    // MARK: MRR mix

    private func mrrMix(_ s: Summary) -> some View {
        let m = s.mrr
        let fixedN = m?.fixedClients ?? 0, perLeadN = m?.perLeadClients ?? 0, commN = m?.commissionClients ?? 0
        let items: [(String, Int, Color, String)] = [
            ("Fixed monthly", fixedN, Theme.violet, Fmt.money(m?.fixed)),
            ("Per lead", perLeadN, Theme.info, Fmt.money(m?.perLeadRunRate)),
            ("Commission", commN, Theme.warn, "On won jobs"),
        ]
        let totalN = max(fixedN + perLeadN + commN, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Label("How clients pay", systemImage: "chart.pie.fill").font(.headline)
            HStack(spacing: 18) {
                Chart {
                    ForEach(items.indices, id: \.self) { i in
                        SectorMark(angle: .value("Clients", items[i].1), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(items[i].2.gradient)
                            .cornerRadius(4)
                    }
                }
                .frame(width: 110, height: 110)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(totalN)").font(.rounded(24)).monospacedDigit()
                        Text("billed").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(items[i].2).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(items[i].0) · \(items[i].1)").font(.subheadline.weight(.semibold))
                                Text(items[i].3).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    // MARK: Aging

    private var aging: some View {
        let lines = store.unpaidLines
        let buckets = Analytics.aging(lines)
        let maxItems = max(buckets.map(\.items).max() ?? 1, 1)
        let colors: [Color] = [Theme.calls, Theme.warn, Color(red: 1, green: 0.45, blue: 0.2), Theme.bad]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Unpaid by age", systemImage: "hourglass").font(.headline)
                Spacer()
                Text("\(lines.count) items").font(.subheadline).foregroundStyle(.secondary)
            }
            if lines.isEmpty {
                Label("Everything is paid", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.calls)
            } else {
                ForEach(buckets) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(b.title).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(b.items == 0 ? "None" : Fmt.money(b.amount))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(b.items == 0 ? .secondary : .primary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(colors[min(b.level, colors.count - 1)].gradient)
                                    .frame(width: b.items == 0 ? 0 : max(10, geo.size.width * CGFloat(b.items) / CGFloat(maxItems)))
                            }
                        }
                        .frame(height: 8)
                        Text("\(b.items) \(b.items == 1 ? "item" : "items")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Who owes

    private var owing: some View {
        let owing = store.clients.filter { !($0.unpaid?.isZero ?? true) }
            .sorted { ($0.unpaid?.eur ?? 0) * 11 + ($0.unpaid?.sek ?? 0) > ($1.unpaid?.eur ?? 0) * 11 + ($1.unpaid?.sek ?? 0) }
        let lines = store.unpaidLines
        return Group {
            if !owing.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Who owes", subtitle: "Tap a client for the full history")
                    VStack(spacing: 0) {
                        ForEach(Array(owing.enumerated()), id: \.element.id) { i, c in
                            let mine = lines.filter { $0.clientId == c.clientId }
                            let oldest = mine.map(\.days).max() ?? 0
                            NavigationLink(value: c) {
                                HStack(spacing: 12) {
                                    Monogram(name: c.displayName, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(mine.isEmpty ? "Open balance" : "\(mine.count) \(mine.count == 1 ? "item" : "items") · oldest \(max(oldest, 0)) days")
                                            .font(.caption)
                                            .foregroundStyle(oldest > 60 ? Theme.bad : .secondary)
                                    }
                                    Spacer()
                                    Text(Fmt.money(c.unpaid))
                                        .font(.rounded(16, .semibold))
                                        .foregroundStyle(.primary)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .zoomSource("client-\(c.clientId)", ns)
                            if i < owing.count - 1 { Divider().padding(.leading, 64) }
                        }
                    }
                    .card(padding: 4)
                }
            }
        }
    }

    // MARK: Open Stripe invoices

    private func openInvoices(_ s: Summary) -> some View {
        let open = s.invoices?.open ?? []
        return Group {
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Open invoices", subtitle: "Sent through Stripe")
                    VStack(spacing: 0) {
                        ForEach(Array(open.enumerated()), id: \.element.id) { i, inv in
                            let row = HStack(spacing: 12) {
                                Image(systemName: inv.overdue == true ? "exclamationmark.circle.fill" : "clock.fill")
                                    .font(.title3)
                                    .foregroundStyle(inv.overdue == true ? Theme.bad : Theme.warn)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.client ?? "Client").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("Due \(Fmt.shortDate(inv.dueDate)) · \(inv.number ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(inv.overdue == true ? Theme.bad : .secondary)
                                }
                                Spacer()
                                Text(Fmt.amount(inv.amount, inv.currency))
                                    .font(.rounded(16, .semibold))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                                if inv.url != nil {
                                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())

                            if let u = inv.url, let url = URL(string: u) {
                                Link(destination: url) { row }.buttonStyle(.plain)
                            } else {
                                row
                            }
                            if i < open.count - 1 { Divider().padding(.leading, 48) }
                        }
                    }
                    .card(padding: 4)
                }
            }
        }
    }
}
