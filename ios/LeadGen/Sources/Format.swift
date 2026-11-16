import Foundation
import SwiftUI

enum Fmt {
    static let sv = Locale(identifier: "sv_SE")

    static func number(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.locale(sv))
    }
    static func sek(_ v: Double) -> String { "\(number(v)) kr" }
    static func eur(_ v: Double) -> String { "€\(number(v))" }
    static func amount(_ v: Double?, _ currency: String?) -> String {
        (currency ?? "").uppercased() == "EUR" ? eur(v ?? 0) : sek(v ?? 0)
    }
    static func money(_ m: Money?) -> String {
        guard let m else { return "0 kr" }
        var parts: [String] = []
        if m.sek != 0 { parts.append(sek(m.sek)) }
        if m.eur != 0 { parts.append(eur(m.eur)) }
        return parts.isEmpty ? "0 kr" : parts.joined(separator: " + ")
    }

    // MARK: Dates

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s = s?.trimmed, !s.isEmpty else { return nil }
        if s.count == 10 { return day.date(from: s) }
        if s.count == 7 { return month.date(from: s) }
        if let d = isoFrac.date(from: s) ?? iso.date(from: s) { return d }
        // Postgres can send 6 fractional digits; drop them and retry.
        if let dot = s.firstIndex(of: ".") {
            var rest = s[s.index(after: dot)...]
            while let c = rest.first, c.isNumber { rest = rest.dropFirst() }
            return iso.date(from: String(s[..<dot]) + rest)
        }
        return nil
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        if abs(date.timeIntervalSinceNow) < 60 { return "Just now" }
        return date.formatted(.relative(presentation: .named))
    }

    static func shortDate(_ s: String?) -> String {
        guard let d = parse(s) else { return s ?? "" }
        if s?.count == 7 { return d.formatted(.dateTime.month(.wide).year()) }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func percentChange(_ now: Int, _ prev: Int) -> Int? {
        guard prev > 0 else { return nil }
        return Int(((Double(now) - Double(prev)) / Double(prev) * 100).rounded())
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        let m = Int(s) / 60, r = Int(s) % 60
        return m > 0 ? "\(m) min \(r) s" : "\(r) s"
    }

    static func statusLabel(_ s: String?) -> String {
        switch s ?? "new" {
        case "new": return "New"
        case "contacted": return "Contacted"
        case "quoted": return "Quoted"
        case "won": return "Won"
        case "won_unfinished": return "Won, not done"
        case "won_completed": return "Won, done"
        case "lost": return "Lost"
        case "not_applicable": return "Not relevant"
        case "no_answer": return "No answer"
        case let other: return other.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusColor(_ s: String?) -> Color {
        switch s ?? "new" {
        case "new": return .blue
        case "contacted": return .indigo
        case "quoted": return .purple
        case "won", "won_unfinished", "won_completed": return .green
        case "no_answer": return .orange
        default: return .gray
        }
    }

    static func telURL(_ phone: String?) -> URL? {
        guard let p = phone?.filter({ $0.isNumber || $0 == "+" }), !p.isEmpty else { return nil }
        return URL(string: "tel:\(p)")
    }
    static func smsURL(_ phone: String?) -> URL? {
        guard let p = phone?.filter({ $0.isNumber || $0 == "+" }), !p.isEmpty else { return nil }
        return URL(string: "sms:\(p)")
    }
    static func mailURL(_ email: String?) -> URL? {
        guard let e = email?.trimmed, e.contains("@") else { return nil }
        return URL(string: "mailto:\(e)")
    }
}
