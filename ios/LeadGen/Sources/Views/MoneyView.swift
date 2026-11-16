import SwiftUI

struct MoneyView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if let s = store.summary {
                    content(s)
                } else if store.isRefreshing {
                    Section { SkeletonRows(count: 5) }
                } else {
                    ContentUnavailableView("No numbers yet", systemImage: "creditcard", description: Text(store.errorMessage ?? "Pull down to refresh."))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Money")
            .refreshable { await store.refresh() }
            .toolbar { ToolbarItem(placement: .topBarLeading) { AccountMenu() } }
            .appDestinations()
        }
    }

    @ViewBuilder
    private func content(_ s: Summary) -> some View {
        let mrr = s.mrr
        let inv = s.invoices
        let open = inv?.open ?? []
        let overdue = open.filter { $0.overdue == true }
        let current = open.filter { $0.overdue != true }
        let manual = inv?.outstandingManual ?? []

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Monthly recurring revenue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Fmt.money(mrr?.total))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(mrr?.activeClients ?? 0) active clients")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            LabeledContent("Fixed fees", value: Fmt.money(mrr?.fixed))
            LabeledContent("Per lead, last 30 days", value: Fmt.money(mrr?.perLeadRunRate))
            LabeledContent("Clients on fixed fee", value: "\(mrr?.fixedClients ?? 0)")
            LabeledContent("Clients billed per lead", value: "\(mrr?.perLeadClients ?? 0)")
            if (mrr?.commissionClients ?? 0) > 0 {
                LabeledContent("Commission clients", value: "\(mrr?.commissionClients ?? 0)")
            }
        }

        Section("Paid") {
            LabeledContent(monthName(s.paid?.thisMonthKey, fallback: "This month"), value: Fmt.money(s.paid?.thisMonth))
            LabeledContent(monthName(s.paid?.lastMonthKey, fallback: "Last month"), value: Fmt.money(s.paid?.lastMonth))
        }

        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unpaid").font(.subheadline).foregroundStyle(.secondary)
                    Text(Fmt.money(inv?.unpaid)).font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Overdue").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(overdue.count)")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundStyle(overdue.isEmpty ? Color.primary : Color.red)
                }
            }
            .padding(.vertical, 4)
        }

        if !overdue.isEmpty {
            Section("Overdue") {
                ForEach(overdue) { openRow($0) }
            }
        }
        if !current.isEmpty {
            Section("Open invoices") {
                ForEach(current) { openRow($0) }
            }
        }
        if !manual.isEmpty {
            Section {
                ForEach(manual) { m in
                    clientLink(m.clientId) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.client ?? m.clientId ?? "Client")
                                Text(Fmt.shortDate(m.month)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.amount(m.amount, m.currency)).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Sent by Wise or email, not paid yet")
            }
        }
        if open.isEmpty && manual.isEmpty {
            Section {
                Label("Every invoice is paid.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }

        Section {
            approvalRow("Waiting for approval", s.approvals?.pendingApproval ?? 0, "clock.badge.exclamationmark", .orange)
            approvalRow("Needs review", s.approvals?.needsReview ?? 0, "exclamationmark.bubble", .red)
            approvalRow("Email drafted, not sent", s.approvals?.gmailDrafted ?? 0, "envelope.badge", .blue)
            Button {
                if let url = URL(string: "https://leadgen-admin-alpha.vercel.app/billing") { openURL(url) }
            } label: {
                Label("Review in web admin", systemImage: "safari")
            }
        } header: {
            Text("Invoice drafts")
        } footer: {
            Text("Approving and sending stays in the web admin.")
        }
    }

    private func openRow(_ i: OpenInvoice) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(i.client ?? i.clientId ?? "Client").lineLimit(1)
                Text([i.number, i.dueDate.map { "due \(Fmt.shortDate($0))" }].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(i.overdue == true ? Color.red : Color.secondary)
            }
            Spacer()
            Text(Fmt.amount(i.amount, i.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
            if let s = i.url, let url = URL(string: s) {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open invoice")
            }
        }
    }

    @ViewBuilder
    private func clientLink<L: View>(_ id: String?, @ViewBuilder label: () -> L) -> some View {
        if let c = store.client(id) {
            NavigationLink(value: c) { label() }
        } else {
            label()
        }
    }

    private func approvalRow(_ title: String, _ count: Int, _ symbol: String, _ tint: Color) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(count > 0 ? tint : Color.secondary)
            Spacer()
            Text("\(count)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
        }
    }

    private func monthName(_ key: String?, fallback: String) -> String {
        guard let key, let d = Fmt.parse(key) else { return fallback }
        return d.formatted(.dateTime.month(.wide))
    }
}
