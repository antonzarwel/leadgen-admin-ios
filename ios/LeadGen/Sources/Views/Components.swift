import SwiftUI
import Charts

struct KPICard: View {
    var title: String
    var value: String
    var subtitle: String?
    var systemImage: String
    var tint: Color = .accentColor
    var trend: Int?
    var trendUpIsGood = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                if let trend { TrendBadge(percent: trend, upIsGood: trendUpIsGood) }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct TrendBadge: View {
    var percent: Int
    var upIsGood = true

    private var good: Bool { percent == 0 ? true : (percent > 0) == upIsGood }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: percent > 0 ? "arrow.up.right" : percent < 0 ? "arrow.down.right" : "arrow.right")
            Text("\(abs(percent))%")
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(percent == 0 ? Color.secondary : (good ? Color.green : Color.red))
        .background((percent == 0 ? Color.gray : (good ? Color.green : Color.red)).opacity(0.14), in: Capsule())
        .accessibilityLabel(percent >= 0 ? "Up \(percent) percent" : "Down \(abs(percent)) percent")
    }
}

struct KindIcon: View {
    var kind: LeadKind
    var size: CGFloat = 36

    var color: Color {
        switch kind {
        case .form: return .blue
        case .call: return .green
        case .missed: return .red
        case .phone: return .teal
        }
    }

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityLabel(kind.label)
    }
}

struct StatusBadge: View {
    var status: String?

    var body: some View {
        Text(Fmt.statusLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Fmt.statusColor(status))
            .background(Fmt.statusColor(status).opacity(0.14), in: Capsule())
    }
}

struct Pill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct LeadRow: View {
    var lead: Lead
    var showClient = true

    var body: some View {
        HStack(spacing: 12) {
            KindIcon(kind: lead.leadKind)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(lead.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if lead.isTestLead { Pill(text: "Test", color: .orange) }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.time(lead.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let s = lead.status, s != "new" { StatusBadge(status: s) }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showClient, let c = lead.client { parts.append(c) }
        if let d = lead.domain { parts.append(d) }
        if parts.isEmpty { parts.append(lead.leadKind.label) }
        return parts.joined(separator: " · ")
    }
}

struct LeadsChart: View {
    var points: [ChartPoint]
    var height: CGFloat = 170

    var body: some View {
        Chart(points) { p in
            BarMark(
                x: .value("Day", p.day, unit: .day),
                y: .value("Leads", p.count)
            )
            .foregroundStyle(by: .value("Type", p.series))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(["Forms": Color.blue, "Calls": Color.green])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(position: .top, alignment: .trailing)
        .frame(height: height)
        .accessibilityLabel("Leads per day")
    }
}

struct SectionCard<Content: View>: View {
    var title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Grey rows shown while the first load runs.
struct SkeletonRows: View {
    var count = 8

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                Circle().fill(Color(.systemFill)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill)).frame(width: 150, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 210, height: 10)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

struct Shimmer: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Shared toolbar menu: refresh state, web admin, sign out.
struct AccountMenu: View {
    @Environment(AppStore.self) private var store
    @State private var confirmSignOut = false

    var body: some View {
        Menu {
            if let d = store.lastUpdated {
                Text("Updated \(Fmt.relative(d))")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Link(destination: APIClient.webAdminURL) {
                Label("Open web admin", systemImage: "safari")
            }
            Divider()
            Button(role: .destructive) {
                confirmSignOut = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            if store.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
        .accessibilityLabel("Account")
        .confirmationDialog("Sign out of Lead Gen?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { store.signOut() }
        } message: {
            Text("Saved data is removed from this iPhone.")
        }
    }
}

/// Lead, client and site screens are reachable from every tab.
struct AppDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Lead.self) { LeadDetailView(lead: $0) }
            .navigationDestination(for: Client.self) { ClientDetailView(clientId: $0.clientId) }
            .navigationDestination(for: Site.self) { SiteDetailView(domain: $0.domain) }
            .navigationDestination(for: LeadFilterRoute.self) { route in
                LeadsListView(filter: route.filter, title: route.title)
            }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}

struct LeadFilterRoute: Hashable {
    var title: String
    var filter: LeadFilter
}
