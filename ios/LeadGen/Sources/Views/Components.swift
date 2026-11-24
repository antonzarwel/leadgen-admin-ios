import SwiftUI
import Charts

// MARK: Numbers

/// A number that counts up on first appear and rolls its digits on change.
struct RollingNumber: View {
    var value: Double
    var format: (Double) -> String
    @State private var shown: Double = 0
    @State private var appeared = false

    var body: some View {
        Text(format(shown))
            .contentTransition(.numericText(value: shown))
            .monospacedDigit()
            .onAppear {
                guard !appeared else { return }
                appeared = true
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.05)) { shown = value }
            }
            .onChange(of: value) { _, new in
                withAnimation(.snappy) { shown = new }
            }
    }
}

struct DeltaChip: View {
    var percent: Int?
    var upIsGood = true
    var onDark = false
    var suffix: String? = nil

    var body: some View {
        if let p = percent {
            let good = p == 0 ? true : (p > 0) == upIsGood
            let color: Color = p == 0 ? .secondary : (good ? Theme.calls : Theme.bad)
            HStack(spacing: 3) {
                Image(systemName: p > 0 ? "arrow.up.right" : p < 0 ? "arrow.down.right" : "equal")
                    .font(.caption2.weight(.heavy))
                Text("\(abs(p))%")
                if let suffix { Text(suffix).fontWeight(.medium).opacity(0.8) }
            }
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(onDark ? Color.white : color)
            .background(onDark ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(color.opacity(0.14)), in: Capsule())
            .accessibilityLabel(p >= 0 ? "Up \(p) percent" : "Down \(abs(p)) percent")
        }
    }
}

// MARK: Avatars and chips

struct Avatar: View {
    var name: String
    var size: CGFloat = 40
    var symbol: String = "person.fill"

    var body: some View {
        let colors = Theme.avatarColors(name)
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                if let i = Fmt.initials(name) {
                    Text(i)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

/// Square monogram for companies and sites.
struct Monogram: View {
    var name: String
    var size: CGFloat = 44

    var body: some View {
        let colors = Theme.avatarColors(name)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(Fmt.initials(name) ?? "?")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct LeadAvatar: View {
    var lead: Lead
    var size: CGFloat = 44

    var body: some View {
        let hasName = !(lead.name?.trimmed.isEmpty ?? true)
        Avatar(name: hasName ? lead.title : "", size: size, symbol: lead.leadKind.isCall ? "phone.fill" : "person.fill")
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: lead.leadKind.symbol)
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .background(Theme.tint(for: lead.leadKind).gradient, in: Circle())
                    .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2) }
                    .offset(x: 3, y: 3)
            }
    }
}

struct Chip: View {
    var text: String
    var color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct StatusChip: View {
    var status: String?
    var body: some View { Chip(text: Fmt.statusLabel(status), color: Fmt.statusColor(status)) }
}

struct FilterChip: View {
    var title: String
    var count: Int?
    var isOn: Bool
    var color: Color = Theme.violet
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .opacity(isOn ? 0.85 : 0.55)
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .overlay { Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 0.5) }
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

// MARK: Lead row

struct LeadRow: View {
    var lead: Lead
    var showClient = true
    var timeStyle: TimeStyle = .clock

    enum TimeStyle { case clock, ago }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LeadAvatar(lead: lead)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(lead.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(timeStyle == .ago ? Fmt.ago(lead.date) : Fmt.time(lead.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Chip(text: kindText, color: Theme.tint(for: lead.leadKind), symbol: lead.leadKind.symbol)
                    if lead.hasCardMetadata {
                        Chip(text: lead.pillText, color: lead.pillColor)
                    } else if let s = lead.status, s != "new" {
                        StatusChip(status: s)
                    }
                    if !lead.hasCardMetadata, (lead.status == nil || lead.status == "new"), let d = lead.date, Date().timeIntervalSince(d) < 86_400 {
                        Chip(text: "New", color: Theme.info, symbol: "sparkle")
                    }
                    if lead.isTestLead { Chip(text: "Test", color: Theme.warn) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var kindText: String {
        if lead.leadKind == .call, let d = Fmt.duration(lead.durationS) { return "Call \(d)" }
        return lead.leadKind.label
    }

    private var subtitle: String {
        var parts: [String] = []
        if showClient, let c = lead.client, !lead.isUnassigned { parts.append(c) }
        if let service = lead.inferredService, service.caseInsensitiveCompare(lead.title) != .orderedSame { parts.append(service) }
        if let d = lead.domain { parts.append(d) }
        if let loc = lead.inferredLocation { parts.append(loc) }
        if parts.isEmpty { parts.append(Fmt.sourceLabel(lead.source)) }
        return parts.joined(separator: " · ")
    }

    private var snippet: String? {
        guard let m = lead.message?.trimmed, !m.isEmpty else { return nil }
        let lines = m.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
        // Prefer the free text over "Key: value" form fields.
        let free = lines.last { !$0.contains(":") } ?? lines.first
        return free
    }
}

// MARK: Charts

struct Sparkline: View {
    var values: [Double]
    var color: Color = Theme.violet
    var lineWidth: CGFloat = 2
    var fill = true

    var body: some View {
        let top = max(values.max() ?? 1, 1)
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                if fill {
                    AreaMark(x: .value("i", item.offset), y: .value("v", item.element))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                LineMark(x: .value("i", item.offset), y: .value("v", item.element))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(top * 1.08))
        .accessibilityHidden(true)
    }
}

/// Small bar sparkline used on tiles.
struct MiniBars: View {
    var values: [Double]
    var color: Color = Theme.violet

    var body: some View {
        let top = max(values.max() ?? 1, 1)
        GeometryReader { geo in
            let n = max(values.count, 1)
            let gap: CGFloat = 2
            let w = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: min(w / 2, 2), style: .continuous)
                        .fill(item.element > 0 ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15)))
                        .frame(width: w, height: max(2, geo.size.height * CGFloat(item.element / top)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

enum ChartGranularity { case day, week }

/// Stacked lead bars with press and drag scrubbing, like Stocks and Health.
struct LeadsBarChart: View {
    var data: [DayValue]
    var granularity: ChartGranularity = .day
    @Binding var selection: Date?
    var height: CGFloat = 200

    private var unit: Calendar.Component { granularity == .day ? .day : .weekOfYear }

    private func matches(_ d: DayValue) -> Bool {
        guard let selection else { return true }
        return Calendar.current.isDate(d.day, equalTo: selection, toGranularity: unit)
    }

    var body: some View {
        Chart {
            ForEach(data) { d in
                let dim = selection != nil && !matches(d)
                BarMark(x: .value("Day", d.day, unit: unit), y: .value("Leads", d.forms))
                    .foregroundStyle(by: .value("Type", "Forms"))
                    .opacity(dim ? 0.3 : 1)
                BarMark(x: .value("Day", d.day, unit: unit), y: .value("Leads", d.calls))
                    .foregroundStyle(by: .value("Type", "Calls"))
                    .opacity(dim ? 0.3 : 1)
                BarMark(x: .value("Day", d.day, unit: unit), y: .value("Leads", d.missed))
                    .foregroundStyle(by: .value("Type", "Missed"))
                    .opacity(dim ? 0.3 : 1)
            }
            if let sel = data.first(where: { selection != nil && matches($0) }) {
                RuleMark(x: .value("Day", sel.day, unit: unit))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
            }
        }
        .chartForegroundStyleScale(["Forms": Theme.forms, "Calls": Theme.calls, "Missed": Theme.missed])
        .chartLegend(.hidden)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                AxisValueLabel().foregroundStyle(Color.secondary)
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selection.map { Calendar.current.startOfDay(for: $0) })
        .accessibilityLabel("Leads chart")
    }
}

/// Legend dots for forms, calls and missed calls.
struct LeadLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            dot("Forms", Theme.forms)
            dot("Calls", Theme.calls)
            dot("Missed", Theme.missed)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func dot(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t)
        }
    }
}

/// A chart card header that shows totals, or the scrubbed value while dragging.
struct ScrubHeader: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(value)
                .font(.rounded(30))
                .contentTransition(.numericText())
                .monospacedDigit()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RangePicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let on = opt.0 == selection
                Button {
                    withAnimation(.snappy) { selection = opt.0 }
                } label: {
                    Text(opt.1)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .background {
                            if on {
                                Capsule().fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: Section chrome

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct MetricTile: View {
    var title: String
    var symbol: String
    var tint: Color
    var value: String
    var extra: String? = nil
    var percent: Int? = nil
    var upIsGood = true
    var caption: String? = nil
    var spark: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.rounded(24))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if let extra {
                    Text("+ \(extra)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                if percent != nil {
                    DeltaChip(percent: percent, upIsGood: upIsGood)
                } else if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if spark.count > 1 {
                    Sparkline(values: spark, color: tint, lineWidth: 1.6)
                        .frame(width: 64, height: 26)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Loading, empty and error states

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.7

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}

struct SkeletonLeadCards: View {
    var count = 6

    var body: some View {
        VStack(spacing: 22) {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SkeletonBlock(width: 88, height: 18, radius: 9)
                        Spacer()
                        SkeletonBlock(width: 42, height: 12)
                    }
                    SkeletonBlock(width: CGFloat(150 + (i * 29) % 90), height: 16)
                    SkeletonBlock(width: CGFloat(190 + (i * 17) % 60), height: 12)
                    HStack(spacing: 6) {
                        SkeletonBlock(width: 64, height: 18, radius: 9)
                        SkeletonBlock(width: 72, height: 18, radius: 9)
                    }
                    SkeletonBlock(height: 36, radius: 12)
                }
            }
        }
        .shimmering()
        .accessibilityLabel("Loading leads")
    }
}

struct SkeletonRows: View {
    var count = 6

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<count, id: \.self) { i in
                HStack(spacing: 12) {
                    Circle().fill(Color(.tertiarySystemFill)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(width: CGFloat(120 + (i * 37) % 80), height: 13)
                        SkeletonBlock(width: CGFloat(170 + (i * 53) % 70), height: 10)
                        SkeletonBlock(width: 60, height: 14, radius: 7)
                    }
                    Spacer()
                }
            }
        }
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = Theme.violet
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 96, height: 96)
                Circle().fill(tint.opacity(0.18)).frame(width: 68, height: 68)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint.gradient)
            }
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct ErrorBanner: View {
    var message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warn)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.warn.opacity(0.35), lineWidth: 0.5) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: Toolbar

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
            ZStack {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("AZ")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.hero, in: Circle())
                }
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Account")
        .confirmationDialog("Sign out of Lead Gen?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { store.signOut() }
        } message: {
            Text("Saved data is removed from this iPhone.")
        }
    }
}

// MARK: Navigation

/// Lead, client and site screens are reachable from every tab.
struct AppDestinations: ViewModifier {
    var ns: Namespace.ID

    func body(content: Content) -> some View {
        content
            .environment(\.zoomNamespace, ns)
            .navigationDestination(for: Lead.self) { lead in
                LeadDetailView(lead: lead).zoomDestination("lead-\(lead.id)", ns).environment(\.zoomNamespace, ns)
            }
            .navigationDestination(for: Client.self) { c in
                ClientDetailView(clientId: c.clientId).zoomDestination("client-\(c.clientId)", ns).environment(\.zoomNamespace, ns)
            }
            .navigationDestination(for: Site.self) { s in
                SiteDetailView(domain: s.domain).zoomDestination("site-\(s.domain)", ns).environment(\.zoomNamespace, ns)
            }
            .navigationDestination(for: LeadFilterRoute.self) { route in
                LeadCardsScreen(starting: route.filter, baseline: route.filter, title: route.title, isRoot: false)
                    .environment(\.zoomNamespace, ns)
            }
    }
}

extension View {
    func appDestinations(_ ns: Namespace.ID) -> some View { modifier(AppDestinations(ns: ns)) }
}

struct LeadFilterRoute: Hashable {
    var title: String
    var filter: LeadFilter
}
