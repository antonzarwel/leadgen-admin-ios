import Foundation

/// Lead counts for one day (or one week) split by type.
struct DayValue: Identifiable, Hashable {
    var day: Date
    var forms = 0
    var calls = 0
    var missed = 0
    var total: Int { forms + calls + missed }
    var id: Date { day }
}

struct MonthRevenue: Identifiable, Hashable {
    var month: Date
    var eur: Double
    var sek: Double
    var id: Date { month }
    func value(_ c: Currency) -> Double { c == .eur ? eur : sek }
}

enum Currency: String, CaseIterable, Identifiable {
    case eur = "EUR", sek = "SEK"
    var id: String { rawValue }
    var label: String { self == .eur ? "EUR" : "SEK" }
    func format(_ v: Double) -> String { self == .eur ? Fmt.eur(v) : Fmt.sek(v) }
}

struct AgingBucket: Identifiable, Hashable {
    var title: String
    var items: Int
    var amount: Money
    var level: Int   // 0 calm ... 3 urgent
    var id: String { title }
}

struct UnpaidLine: Identifiable, Hashable {
    var clientId: String?
    var client: String
    var label: String
    var amount: Double
    var currency: String?
    var days: Int          // days since due (negative means not due yet)
    var url: String?
    var id: String { [clientId ?? client, label, currency ?? ""].joined(separator: "|") }
}

/// Precomputed lookups so lists with sparklines stay fast.
struct LeadIndex {
    var real: [Lead] = []
    var byClient: [String: [Lead]] = [:]
    var byDomain: [String: [Lead]] = [:]

    init() {}

    init(_ leads: [Lead]) {
        real = leads.filter { !$0.isTestLead }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for l in real {
            if let c = l.clientId { byClient[c, default: []].append(l) }
            if let d = l.domain { byDomain[d, default: []].append(l) }
        }
    }
}

enum Analytics {
    static var cal: Calendar { Calendar.current }

    static func daily(_ leads: [Lead], days: Int, now: Date = Date()) -> [DayValue] {
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var map: [Date: DayValue] = [:]
        for l in leads {
            guard let d = l.date, d >= start else { continue }
            let day = cal.startOfDay(for: d)
            var v = map[day] ?? DayValue(day: day)
            switch l.leadKind {
            case .call: v.calls += 1
            case .missed: v.missed += 1
            case .form, .phone: v.forms += 1
            }
            map[day] = v
        }
        return (0..<days).compactMap { i in
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            return map[day] ?? DayValue(day: day)
        }
    }

    static func weekly(_ leads: [Lead], weeks: Int, now: Date = Date()) -> [DayValue] {
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) else { return [] }
        var map: [Date: DayValue] = [:]
        for l in leads {
            guard let d = l.date, d >= start, let wk = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            var v = map[wk] ?? DayValue(day: wk)
            switch l.leadKind {
            case .call: v.calls += 1
            case .missed: v.missed += 1
            case .form, .phone: v.forms += 1
            }
            map[wk] = v
        }
        return (0..<weeks).compactMap { i in
            guard let wk = cal.date(byAdding: .weekOfYear, value: i, to: start) else { return nil }
            return map[wk] ?? DayValue(day: wk)
        }
    }

    static func count(_ leads: [Lead], from: Date, to: Date) -> Int {
        leads.reduce(0) { acc, l in
            guard let d = l.date, d >= from, d < to else { return acc }
            return acc + 1
        }
    }

    static func percent(_ now: Int, _ prev: Int) -> Int? { Fmt.percentChange(now, prev) }

    static func percent(_ now: Double, _ prev: Double) -> Int? {
        guard prev > 0 else { return nil }
        return Int(((now - prev) / prev * 100).rounded())
    }

    static func monthlyRevenue(_ clients: [Client]) -> [MonthRevenue] {
        var map: [String: (Double, Double)] = [:]
        for c in clients {
            for p in c.payments ?? [] where (p.status ?? "") == "paid" {
                guard let m = p.month, m.count == 7 else { continue }
                var v = map[m] ?? (0, 0)
                if (p.currency ?? "").uppercased() == "EUR" { v.0 += p.amount ?? 0 } else { v.1 += p.amount ?? 0 }
                map[m] = v
            }
        }
        return map.keys.sorted().compactMap { k in
            guard let d = Fmt.parse(k), let v = map[k] else { return nil }
            return MonthRevenue(month: d, eur: v.0, sek: v.1)
        }
    }

    static func unpaidLines(_ s: Summary?, now: Date = Date()) -> [UnpaidLine] {
        var out: [UnpaidLine] = []
        for inv in s?.invoices?.open ?? [] {
            let due = Fmt.parse(inv.dueDate)
            let days = due.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: now)).day ?? 0 } ?? 0
            out.append(UnpaidLine(clientId: inv.clientId, client: inv.client ?? "Unknown", label: "Invoice \(inv.number ?? "")",
                                  amount: inv.amount ?? 0, currency: inv.currency, days: days, url: inv.url))
        }
        for m in s?.invoices?.outstandingManual ?? [] {
            // A manual month falls due at the end of that month.
            var days = 0
            if let start = Fmt.parse(m.month), let end = cal.date(byAdding: .month, value: 1, to: start) {
                days = cal.dateComponents([.day], from: end, to: now).day ?? 0
            }
            out.append(UnpaidLine(clientId: m.clientId, client: m.client ?? "Unknown", label: Fmt.shortDate(m.month),
                                  amount: m.amount ?? 0, currency: m.currency, days: days, url: nil))
        }
        return out.sorted { $0.days > $1.days }
    }

    static func aging(_ lines: [UnpaidLine]) -> [AgingBucket] {
        let defs: [(String, ClosedRange<Int>, Int)] = [
            ("Not due yet", Int.min...0, 0),
            ("1 to 30 days", 1...30, 1),
            ("31 to 90 days", 31...90, 2),
            ("Over 90 days", 91...Int.max, 3),
        ]
        return defs.map { title, range, level in
            let hits = lines.filter { range.contains($0.days) }
            var m = Money(SEK: 0, EUR: 0)
            for h in hits {
                if (h.currency ?? "").uppercased() == "EUR" { m.EUR = (m.EUR ?? 0) + h.amount } else { m.SEK = (m.SEK ?? 0) + h.amount }
            }
            return AgingBucket(title: title, items: hits.count, amount: m, level: level)
        }
    }
}

extension AppStore {
    var realLeads: [Lead] { index.real }

    func leads(forClient id: String) -> [Lead] { index.byClient[id] ?? [] }
    func leads(forDomain d: String) -> [Lead] { index.byDomain[d] ?? [] }

    var leadsToday: Int {
        let start = Analytics.cal.startOfDay(for: Date())
        return Analytics.count(realLeads, from: start, to: .distantFuture)
    }

    /// Yesterday up to the same time of day, so the comparison is fair.
    var leadsYesterdaySoFar: Int {
        let now = Date()
        guard let y = Analytics.cal.date(byAdding: .day, value: -1, to: now) else { return 0 }
        return Analytics.count(realLeads, from: Analytics.cal.startOfDay(for: y), to: y)
    }

    func leadsInLast(days: Int, offset: Int = 0) -> Int {
        let today = Analytics.cal.startOfDay(for: Date())
        guard let end = Analytics.cal.date(byAdding: .day, value: 1 - offset * days, to: today),
              let start = Analytics.cal.date(byAdding: .day, value: -days, to: end) else { return 0 }
        return Analytics.count(realLeads, from: start, to: end)
    }

    var monthlyRevenue: [MonthRevenue] { Analytics.monthlyRevenue(clients) }

    var unpaidLines: [UnpaidLine] { Analytics.unpaidLines(summary) }

    var payingClients: [Client] { clients.filter { ($0.mrr ?? 0) > 0 } }
}
