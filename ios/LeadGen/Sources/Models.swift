import Foundation

// Every field is optional so a missing or new field on the server never
// breaks decoding. Views read through the non optional helpers.

struct Money: Codable, Hashable {
    var SEK: Double?
    var EUR: Double?

    var sek: Double { SEK ?? 0 }
    var eur: Double { EUR ?? 0 }
    var isZero: Bool { sek == 0 && eur == 0 }
    static let zero = Money(SEK: 0, EUR: 0)
}

// MARK: Summary (/api/m/summary)

struct Summary: Codable, Hashable {
    var generatedAt: String?
    var mrr: MRR?
    var paid: Paid?
    var leads: LeadStats?
    var invoices: InvoiceStats?
    var approvals: Approvals?
    var sites: SiteStats?
    var gsc: GSCStats?
}

struct MRR: Codable, Hashable {
    var fixed: Money?
    var perLeadRunRate: Money?
    var total: Money?
    var fixedClients: Int?
    var perLeadClients: Int?
    var commissionClients: Int?
    var activeClients: Int?
}

struct Paid: Codable, Hashable {
    var thisMonth: Money?
    var lastMonth: Money?
    var thisMonthKey: String?
    var lastMonthKey: String?
}

struct LeadStats: Codable, Hashable {
    var last7: Int?
    var last30: Int?
    var prev30: Int?
    var calls30: Int?
    var forms30: Int?
    var missed7: Int?
    var missed30: Int?
    var daily: [DayCount]?
}

struct DayCount: Codable, Hashable, Identifiable {
    var date: String?
    var total: Int?
    var calls: Int?
    var forms: Int?
    var missed: Int?
    var id: String { date ?? UUID().uuidString }
    var day: Date? { Fmt.parse(date) }
}

struct InvoiceStats: Codable, Hashable {
    var open: [OpenInvoice]?
    var overdueCount: Int?
    var outstandingManual: [ManualDue]?
    var unpaid: Money?
}

struct OpenInvoice: Codable, Hashable, Identifiable {
    var clientId: String?
    var client: String?
    var number: String?
    var amount: Double?
    var currency: String?
    var dueDate: String?
    var overdue: Bool?
    var url: String?
    var id: String { [clientId, number, dueDate].compactMap { $0 }.joined(separator: "|") }
}

struct ManualDue: Codable, Hashable, Identifiable {
    var clientId: String?
    var client: String?
    var month: String?
    var amount: Double?
    var currency: String?
    var id: String { [clientId, month, currency].compactMap { $0 }.joined(separator: "|") }
}

struct Approvals: Codable, Hashable {
    var pendingApproval: Int?
    var needsReview: Int?
    var gmailDrafted: Int?
    var total: Int { (pendingApproval ?? 0) + (needsReview ?? 0) }
}

struct SiteStats: Codable, Hashable {
    var total: Int?
    var rented: Int?
    var free: Int?
    var personal: Int?
}

struct GSCStats: Codable, Hashable {
    var lastDate: String?
    var staleDays: Int?
    var stale: Bool?
    var clicks7d: Int?
    var impressions7d: Int?
    var sitesWithData: Int?
}

// MARK: Leads (/api/m/leads)

struct LeadsResponse: Codable { var leads: [Lead]? }

struct Lead: Codable, Hashable, Identifiable {
    var id: String
    var at: String?
    var clientId: String?
    var client: String?
    var domain: String?
    var source: String?
    var kind: String?
    var name: String?
    var phone: String?
    var email: String?
    var message: String?
    var notes: String?
    var status: String?
    var wonValueSek: Double?
    var followUpDate: String?
    var isTest: Bool?
    var durationS: Double?

    var date: Date? { Fmt.parse(at) }
    var leadKind: LeadKind { LeadKind(rawValue: kind ?? "") ?? .form }
    var title: String {
        if let n = name?.trimmed, !n.isEmpty { return n }
        if let p = phone?.trimmed, !p.isEmpty { return p }
        if let e = email?.trimmed, !e.isEmpty { return e }
        return leadKind == .form ? "Form lead" : "Unknown caller"
    }
    var isTestLead: Bool { isTest == true }
}

enum LeadKind: String, CaseIterable {
    case form, call, missed, phone

    var label: String {
        switch self {
        case .form: return "Form"
        case .call: return "Call"
        case .missed: return "Missed call"
        case .phone: return "Phone lead"
        }
    }
    var symbol: String {
        switch self {
        case .form: return "doc.text.fill"
        case .call: return "phone.fill"
        case .missed: return "phone.down.fill"
        case .phone: return "phone.arrow.up.right.fill"
        }
    }
    var isCall: Bool { self == .call || self == .missed }
}

// MARK: Clients (/api/m/clients)

struct ClientsResponse: Codable { var clients: [Client]? }

struct Client: Codable, Hashable, Identifiable {
    var clientId: String
    var name: String?
    var billingModel: String?
    var billingRate: Double?
    var currency: String?
    var billingMethod: String?
    var mrr: Double?
    var qualified30: Int?
    var d7: Int?
    var d30: Int?
    var calls30: Int?
    var missed30: Int?
    var unpaid: Money?
    var openInvoices: Int?
    var overdueInvoices: Int?
    var email: String?
    var phone: String?
    var entity: String?
    var sites: [ClientSite]?
    var invoices: [Invoice]?
    var payments: [Payment]?

    var id: String { clientId }
    var displayName: String { name ?? clientId }
    var mrrText: String { (mrr ?? 0) > 0 ? Fmt.amount(mrr ?? 0, currency) : "No fee" }
    var modelText: String {
        switch billingModel {
        case "fixed_monthly": return "Fixed monthly"
        case "per_lead": return "Per lead"
        case "per_won_value": return "Commission on won jobs"
        case "revenue_share": return "Revenue share"
        case .some(let other): return other.replacingOccurrences(of: "_", with: " ").capitalized
        case .none: return "Not set"
        }
    }
}

struct ClientSite: Codable, Hashable, Identifiable {
    var domain: String
    var name: String?
    var id: String { domain }
}

struct Invoice: Codable, Hashable, Identifiable {
    var number: String?
    var status: String?
    var amount: Double?
    var currency: String?
    var invoiceDate: String?
    var dueDate: String?
    var paidAt: String?
    var overdue: Bool?
    var url: String?
    var id: String { [number, invoiceDate, status].compactMap { $0 }.joined(separator: "|") }
}

struct Payment: Codable, Hashable, Identifiable {
    var month: String?
    var amount: Double?
    var currency: String?
    var status: String?
    var id: String { [month, currency, status].compactMap { $0 }.joined(separator: "|") }
}

// MARK: Sites (/api/m/sites)

struct SitesResponse: Codable { var sites: [Site]? }

struct Site: Codable, Hashable, Identifiable {
    var domain: String
    var name: String?
    var status: String?
    var clientId: String?
    var client: String?
    var kind: String?
    var d7: Int?
    var d30: Int?
    var d90: Int?
    var gsc: SiteGSC?
    var id: String { domain }
    var siteKind: SiteKind { SiteKind(rawValue: kind ?? "") ?? .free }
    var url: URL? { URL(string: "https://\(domain)") }
}

struct SiteGSC: Codable, Hashable {
    var date: String?
    var clicks: Int?
    var impressions: Int?
}

enum SiteKind: String, CaseIterable, Identifiable {
    case rented, free, personal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rented: return "Rented"
        case .free: return "Free"
        case .personal: return "Own"
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
