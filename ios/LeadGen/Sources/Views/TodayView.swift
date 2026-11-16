import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let msg = store.errorMessage { ErrorBanner(message: msg) }

                    if let s = store.summary {
                        kpis(s)
                        if let a = s.approvals, a.total > 0 { approvals(a) }
                        chartCard
                        recentCard
                        if let g = s.gsc, g.stale == true { gscNote(g) }
                    } else if store.isRefreshing || store.errorMessage == nil {
                        placeholder
                    } else {
                        ContentUnavailableView {
                            Label("No data yet", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("Pull down to try again.")
                        } actions: {
                            Button("Try Again") { Task { await store.refresh() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 360)
                    }

                    if let d = store.lastUpdated {
                        Text("Updated \(Fmt.relative(d))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.refresh() }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
            }
            .appDestinations()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func kpis(_ s: Summary) -> some View {
        let l = s.leads
        let last7 = l?.last7 ?? 0
        let last30 = l?.last30 ?? 0
        let prev7 = previousWeek(s)
        let overdue = s.invoices?.overdueCount ?? 0
        let missed7 = l?.missed7 ?? 0

        LazyVGrid(columns: columns, spacing: 12) {
            KPICard(title: "Leads 7 days", value: "\(last7)", subtitle: prev7.map { "vs \($0) week before" },
                    systemImage: "tray.full.fill", tint: .blue,
                    trend: prev7.flatMap { Fmt.percentChange(last7, $0) })
            KPICard(title: "Leads 30 days", value: "\(last30)", subtitle: "\(l?.calls30 ?? 0) calls, \(l?.forms30 ?? 0) forms",
                    systemImage: "chart.bar.fill", tint: .indigo,
                    trend: Fmt.percentChange(last30, l?.prev30 ?? 0))
            KPICard(title: "Missed calls", value: "\(missed7)", subtitle: "This week, \(l?.missed30 ?? 0) in 30 days",
                    systemImage: "phone.down.fill", tint: missed7 > 0 ? .red : .green)
            KPICard(title: "Unpaid", value: Fmt.money(s.invoices?.unpaid), subtitle: overdue > 0 ? "\(overdue) overdue" : "Nothing overdue",
                    systemImage: "exclamationmark.circle.fill", tint: overdue > 0 ? .red : .orange)
            KPICard(title: "MRR", value: Fmt.money(s.mrr?.total), subtitle: "\(s.mrr?.activeClients ?? 0) active clients",
                    systemImage: "arrow.triangle.2.circlepath", tint: .green)
            KPICard(title: "Paid this month", value: Fmt.money(s.paid?.thisMonth), subtitle: "Last month \(Fmt.money(s.paid?.lastMonth))",
                    systemImage: "checkmark.seal.fill", tint: .teal)
        }
    }

    private func previousWeek(_ s: Summary) -> Int? {
        guard let daily = s.leads?.daily, daily.count >= 14 else { return nil }
        let slice = daily.suffix(14).prefix(7)
        return slice.reduce(0) { $0 + ($1.total ?? 0) }
    }

    private func approvals(_ a: Approvals) -> some View {
        Button {
            store.selectedTab = .money
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.clock.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(a.total) invoice \(a.total == 1 ? "draft" : "drafts") to review")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(a.pendingApproval ?? 0) waiting for approval, \(a.needsReview ?? 0) need review")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var chartCard: some View {
        SectionCard(title: "Leads per day", trailing: "Last 30 days") {
            LeadsChart(points: store.daily(days: 30) { _ in true })
        }
    }

    private var recentCard: some View {
        let recent = Array(store.leads.filter { !$0.isTestLead }.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest leads").font(.headline)
                Spacer()
                Button("See All") { store.selectedTab = .leads }
                    .font(.subheadline)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if recent.isEmpty {
                    Text(store.isRefreshing ? "Loading" : "No leads in the last 90 days")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, lead in
                    NavigationLink(value: lead) {
                        HStack {
                            LeadRow(lead: lead)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < recent.count - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func gscNote(_ g: GSCStats) -> some View {
        Label(
            g.staleDays.map { "Search Console data is \($0) days old." } ?? "Search Console has no data yet.",
            systemImage: "magnifyingglass"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    KPICard(title: "Loading", value: "000", subtitle: "Loading data", systemImage: "circle")
                }
            }
            SectionCard(title: "Leads per day") {
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemFill)).frame(height: 170)
            }
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }
}
