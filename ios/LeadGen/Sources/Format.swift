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

    /// Short age like "5 min", "3 h", "2 d".
    static func ago(_ date: Date?) -> String {
        guard let date else { return "" }
        let s = max(0, Date().timeIntervalSince(date))
        if s < 60 { return "Now" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 86_400 { return "\(Int(s / 3600)) h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400)) d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Swedish style phone grouping: 073 904 78 06 or +46 73 904 78 06.
    static func phone(_ raw: String?) -> String {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return "" }
        let digits = raw.filter { $0.isNumber }
        func group(_ s: String) -> String {
            let c = Array(s)
            guard c.count == 9 else { return s }
            return "\(String(c[0..<2])) \(String(c[2..<5])) \(String(c[5..<7])) \(String(c[7..<9]))"
        }
        if raw.hasPrefix("+46") || (digits.hasPrefix("46") && digits.count == 11) {
            return "+46 " + group(String(digits.dropFirst(2)))
        }
        if digits.hasPrefix("0") && digits.count == 10 {
            let c = Array(digits)
            return "\(String(c[0..<3])) \(String(c[3..<6])) \(String(c[6..<8])) \(String(c[8..<10]))"
        }
        return raw
    }

    /// Primary and secondary parts of a two currency amount, EUR first when present.
    static func moneyParts(_ m: Money?) -> (main: String, extra: String?) {
        let m = m ?? .zero
        if m.eur != 0 && m.sek != 0 { return (eur(m.eur), sek(m.sek)) }
        if m.eur != 0 { return (eur(m.eur), nil) }
        return (sek(m.sek), nil)
    }

    static func initials(_ s: String) -> String? {
        let words = s.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return nil }
        if words.count > 1, let second = words[1].first { return String([first, second]).uppercased() }
        return String(first).uppercased()
    }

    static func greeting(_ date: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static func sourceLabel(_ source: String?) -> String {
        switch source ?? "" {
        case "telavox": return "Phone call"
        case "custom_form": return "Website form"
        case "directory-form": return "Directory form"
        case "typeform": return "Typeform"
        case "jotform": return "Jotform"
        case "phone": return "Added by hand"
        case "": return "Unknown"
        case let s: return s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
