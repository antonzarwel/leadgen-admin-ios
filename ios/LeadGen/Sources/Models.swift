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
//
// One card per homeowner request. List: GET /api/m/leads (cursor, default 90 days, max 365).
// Contact is only on GET /api/m/leads/{id}, which returns { lead, with recipients oldest first }.
// A bad row is skipped. A teaser (visibility = teaser) has no name, phone, email, or message.

struct LeadPage: Decodable {
    var leads: [Lead]
    var nextCursor: String?
    var hasMore: Bool
    var total: Int?
    var sites: [LeadSiteOption]
    var verticals: [String]

    init(leads: [Lead], nextCursor: String?, hasMore: Bool, total: Int? = nil, sites: [LeadSiteOption] = [], verticals: [String] = []) {
        self.leads = leads
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.total = total
        self.sites = sites
        self.verticals = verticals
    }

    init(from decoder: Decoder) throws {
        if let rows = try? [Soft<Lead>](from: decoder) {
            leads = rows.compactMap(\.value)
            nextCursor = nil
            hasMore = false
            total = nil
            sites = []
            verticals = []
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rows = Self.rows(c, .leads) ?? Self.rows(c, .cards) ?? Self.rows(c, .items) ?? []
        var cursor = c.flexString(.nextCursor) ?? c.flexString(.next)
        var more = c.flexBool(.hasMore)
        if rows.isEmpty, let nested = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: .data) {
            rows = Self.rows(nested, .leads) ?? Self.rows(nested, .cards) ?? Self.rows(nested, .items) ?? []
            if cursor == nil { cursor = nested.flexString(.nextCursor) ?? nested.flexString(.next) }
            if more == nil { more = nested.flexBool(.hasMore) }
        }
        if rows.isEmpty, let wrapped = try? c.decode([Soft<Lead>].self, forKey: .data) {
            rows = wrapped.compactMap(\.value)
        }
        if cursor == nil, let page = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: .pagination) {
            cursor = page.flexString(.nextCursor) ?? page.flexString(.next) ?? page.flexString(.cursor)
            if more == nil { more = page.flexBool(.hasMore) }
        }
        if let cursor, cursor.isEmpty { cursor = nil }
        leads = rows
        nextCursor = cursor
        if let more {
            hasMore = more && cursor != nil
        } else {
            hasMore = cursor != nil
        }
        total = c.flexInt(.total)
        sites = (try? c.decode([Soft<LeadSiteOption>].self, forKey: .sites))?.compactMap(\.value) ?? []
        verticals = (try? c.decode([String].self, forKey: .verticals)) ?? []
    }

    private static func rows(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Lead]? {
        guard c.contains(key) else { return nil }
        if (try? c.decodeNil(forKey: key)) == true { return [] }
        guard let wrapped = try? c.decode([Soft<Lead>].self, forKey: key) else { return nil }
        return wrapped.compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey {
        case leads, cards, items, data, pagination
        case nextCursor, next, hasMore, cursor, total, sites, verticals
    }
}

struct LeadDetailPayload: Decodable {
    var lead: Lead
    var recipients: [LeadRecipient]
    var note: String?
    var fields: [LeadField]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var card: Lead
        if c.contains(.card), let nested = try? c.decode(Lead.self, forKey: .card) {
            card = nested
        } else if c.contains(.lead), let nested = try? c.decode(Lead.self, forKey: .lead) {
            card = nested
        } else {
            card = try Lead(from: decoder)
        }
        if card.viewerRole == nil {
            card.viewerRole = c.flexString(.viewer) ?? c.flexString(.role)
        }
        if card.viewerClientId == nil {
            card.viewerClientId = c.flexString(.viewerClientId)
        }
        if card.contactHidden == nil, let hidden = c.flexBool(.contactHidden) {
            card.contactHidden = hidden
        }
        if card.contactVisible == nil, let visible = c.flexBool(.contactVisible) {
            card.contactVisible = visible
        }
        if card.ownOfferStatus == nil {
            card.ownOfferStatus = c.flexString(.ownOfferStatus)
        }
        if card.acceptedByViewer == nil {
            card.acceptedByViewer = c.flexBool(.acceptedByViewer)
        }
        if card.billingNote == nil {
            card.billingNote = c.flexString(.billingExplanation) ?? c.flexString(.billedFreeExplanation) ?? c.flexString(.billingNote)
        }
        let decoded = Self.recipients(c, .recipients) ?? Self.recipients(c, .timeline) ?? card.inlineRecipients ?? []
        lead = card
        recipients = decoded
        note = card.billingNote
        fields = Self.fields(c)
    }

    private static func recipients(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [LeadRecipient]? {
        guard c.contains(key) else { return nil }
        guard let rows = try? c.decode([Soft<LeadRecipient>].self, forKey: key) else { return nil }
        return rows.compactMap(\.value)
    }

    private static func fields(_ c: KeyedDecodingContainer<CodingKeys>) -> [LeadField] {
        for key in [CodingKeys.teasers, .highlights, .fields, .calculator] {
            guard c.contains(key) else { continue }
            if let rows = try? c.decode([Soft<LeadField>].self, forKey: key) {
                let list = rows.compactMap(\.value)
                if !list.isEmpty { return list }
            }
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case card, lead, recipients, timeline
        case teasers, highlights, fields, calculator
        case viewer, role, viewerClientId
        case contactHidden, contactVisible, ownOfferStatus, acceptedByViewer
        case billingExplanation, billedFreeExplanation, billingNote
    }
}

struct LeadField: Decodable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { label + "\u{1e}" + value }

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let label = c.flexString(.label) ?? c.flexString(.key) ?? c.flexString(.name) ?? c.flexString(.title) ?? ""
        let value = c.flexString(.value) ?? c.flexString(.text) ?? ""
        if label.isEmpty || value.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "empty field"))
        }
        self.init(label: label, value: value)
    }

    private enum CodingKeys: String, CodingKey {
        case label, key, name, title, value, text
    }
}

struct LeadSlots: Decodable, Hashable {
    var max: Int?
    var won: Int?
    var offered: Int?
    var queued: Int?

    init(max: Int?, won: Int?, offered: Int?, queued: Int?) {
        self.max = max
        self.won = won
        self.offered = offered
        self.queued = queued
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            max: c.flexInt(.max) ?? c.flexInt(.maxSlots),
            won: c.flexInt(.won),
            offered: c.flexInt(.offered),
            queued: c.flexInt(.queued)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case max, won, offered, queued, maxSlots
    }
}

struct AcceptedPeek: Decodable, Hashable {
    var name: String?
    var status: String?
    var at: String?
    var priceSek: Double?
    var billable: Bool?
    var free: Bool?
    var freeN: Int?

    init(name: String?, status: String? = nil, at: String? = nil, priceSek: Double? = nil, billable: Bool? = nil, free: Bool? = nil, freeN: Int? = nil) {
        self.name = name
        self.status = status
        self.at = at
        self.priceSek = priceSek
        self.billable = billable
        self.free = free
        self.freeN = freeN
    }

    init(from decoder: Decoder) throws {
        if let one = try? decoder.singleValueContainer(), let name = try? one.decode(String.self) {
            self.init(name: name)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: c.flexString(.name) ?? c.flexString(.companyName) ?? c.flexString(.company),
            status: c.flexString(.status) ?? c.flexString(.uiStatus),
            at: c.flexString(.at) ?? c.flexString(.acceptedAt),
            priceSek: c.flexDouble(.priceSek) ?? c.flexDouble(.price),
            billable: c.flexBool(.billable),
            free: c.flexBool(.free) ?? c.flexBool(.freeLead),
            freeN: c.flexInt(.freeN)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name, companyName, company, status, uiStatus, at, acceptedAt, priceSek, price, billable, free, freeLead, freeN
    }
}

struct SummaryCounts: Decodable, Hashable {
    var accepted: Int = 0
    var offered: Int = 0
    var queued: Int = 0
    var declined: Int = 0

    init(accepted: Int = 0, offered: Int = 0, queued: Int = 0, declined: Int = 0) {
        self.accepted = accepted
        self.offered = offered
        self.queued = queued
        self.declined = declined
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            accepted: c.flexInt(.accepted) ?? 0,
            offered: c.flexInt(.offered) ?? 0,
            queued: c.flexInt(.queued) ?? 0,
            declined: c.flexInt(.declined) ?? 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accepted, offered, queued, declined
    }
}

struct RecipientsSummary: Decodable, Hashable {
    var accepted: [AcceptedPeek] = []
    var offered: [AcceptedPeek] = []
    var queued: [AcceptedPeek] = []
    var declined: [AcceptedPeek] = []
    var counts: SummaryCounts = SummaryCounts()

    var offeredNames: [String] { offered.compactMap { $0.name?.nilIfBlank } }
    var queuedNames: [String] { queued.compactMap { $0.name?.nilIfBlank } }
    var declinedNames: [String] { declined.compactMap { $0.name?.nilIfBlank } }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accepted = Self.peeks(c, .accepted)
        offered = Self.peeks(c, .offered)
        queued = Self.peeks(c, .queued)
        declined = Self.peeks(c, .declined)
        if let decoded = try? c.decode(SummaryCounts.self, forKey: .counts) {
            counts = decoded
        } else {
            counts = SummaryCounts(accepted: accepted.count, offered: offered.count, queued: queued.count, declined: declined.count)
        }
    }

    private static func peeks(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [AcceptedPeek] {
        guard c.contains(key) else { return [] }
        if let rows = try? c.decode([Soft<AcceptedPeek>].self, forKey: key) {
            return rows.compactMap(\.value).filter { $0.name?.nilIfBlank != nil || $0.at != nil || $0.status != nil }
        }
        if let names = try? c.decode([String].self, forKey: key) {
            return names.map { AcceptedPeek(name: $0) }
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case accepted, offered, queued, declined, counts
    }
}

struct LeadBilling: Decodable, Hashable {
    var mark: String?
    var text: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mark = c.flexString(.mark)
        text = c.flexString(.text)
    }

    private enum CodingKeys: String, CodingKey { case mark, text }
}

struct LeadSiteOption: Decodable, Hashable, Identifiable {
    var domain: String
    var siteName: String?
    var vertical: String?
    var id: String { domain }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let domain = c.flexString(.domain), !domain.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "site has no domain"))
        }
        self.domain = domain
        siteName = c.flexString(.siteName)
        vertical = c.flexString(.vertical)
    }

    private enum CodingKeys: String, CodingKey { case domain, siteName, vertical }
}

struct LeadRecipient: Decodable, Hashable, Identifiable {
    var storedId: String?
    var companyName: String?
    var companySlug: String?
    var clientId: String?
    var email: String?
    var status: String?
    var priceSek: Double?
    var billable: Bool?
    var free: Bool?
    var freeN: Int?
    var tier: String?
    var offeredAt: String?
    var viewedAt: String?
    var acceptedAt: String?
    var declinedAt: String?
    var deliveredAt: String?
    var expiredAt: String?
    var releasedAt: String?
    var contactedAt: String?
    var sendAfter: String?
    var isSelf: Bool?
    var countHint: Int?

    var id: String {
        if let storedId, !storedId.isEmpty { return storedId }
        let parts = [companySlug, companyName, status, offeredAt, acceptedAt, clientId].compactMap { $0?.nilIfBlank }
        if !parts.isEmpty { return parts.joined(separator: "|") }
        return "recipient-\(status ?? "x")-\(countHint ?? 0)"
    }

    var normalizedStatus: String {
        switch (status ?? "").lowercased() {
        case "won": return "accepted"
        case "sending": return "queued"
        case "view", "seen", "opened": return "viewed"
        case "rejected", "no", "no_thanks": return "declined"
        case "":
            if acceptedAt != nil { return "accepted" }
            if declinedAt != nil { return "declined" }
            if viewedAt != nil { return "viewed" }
            if deliveredAt != nil { return "delivered" }
            if offeredAt != nil { return "offered" }
            return "queued"
        default:
            return (status ?? "").lowercased()
        }
    }

    /// Server `ui_status`. There is no viewed event.
    var displayStatus: String { normalizedStatus }

    var isFree: Bool { free == true || (freeN ?? 0) > 0 }

    var timelineDate: Date {
        Fmt.parse(sendAfter) ?? Fmt.parse(offeredAt) ?? Fmt.parse(acceptedAt) ?? Fmt.parse(deliveredAt) ?? Fmt.parse(viewedAt) ?? .distantPast
    }

    init(storedId: String? = nil, companyName: String? = nil, companySlug: String? = nil, clientId: String? = nil, email: String? = nil, status: String? = nil, priceSek: Double? = nil, billable: Bool? = nil, free: Bool? = nil, freeN: Int? = nil, tier: String? = nil, offeredAt: String? = nil, viewedAt: String? = nil, acceptedAt: String? = nil, declinedAt: String? = nil, deliveredAt: String? = nil, expiredAt: String? = nil, releasedAt: String? = nil, contactedAt: String? = nil, sendAfter: String? = nil, isSelf: Bool? = nil, countHint: Int? = nil) {
        self.storedId = storedId
        self.companyName = companyName
        self.companySlug = companySlug
        self.clientId = clientId
        self.email = email
        self.status = status
        self.priceSek = priceSek
        self.billable = billable
        self.free = free
        self.freeN = freeN
        self.tier = tier
        self.offeredAt = offeredAt
        self.viewedAt = viewedAt
        self.acceptedAt = acceptedAt
        self.declinedAt = declinedAt
        self.deliveredAt = deliveredAt
        self.expiredAt = expiredAt
        self.releasedAt = releasedAt
        self.contactedAt = contactedAt
        self.sendAfter = sendAfter
        self.isSelf = isSelf
        self.countHint = countHint
    }

    init(from decoder: Decoder) throws {
        if let one = try? decoder.singleValueContainer(), let name = try? one.decode(String.self) {
            self.init(companyName: name, status: "offered")
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let freeN = c.flexInt(.freeN)
        let free = c.flexBool(.free) ?? c.flexBool(.freeLead) ?? ((freeN ?? 0) > 0 ? true : nil)
        self.init(
            storedId: c.flexString(.recipientId) ?? c.flexString(.id),
            companyName: c.flexString(.companyName) ?? c.flexString(.company) ?? c.flexString(.name),
            companySlug: c.flexString(.companySlug) ?? c.flexString(.slug),
            clientId: c.flexString(.clientId),
            email: c.flexString(.email),
            status: c.flexString(.uiStatus) ?? c.flexString(.status),
            priceSek: c.flexDouble(.priceSek) ?? c.flexDouble(.priceShown) ?? c.flexDouble(.price),
            billable: c.flexBool(.billable),
            free: free,
            freeN: freeN,
            tier: c.flexString(.tier),
            offeredAt: c.flexString(.offeredAt),
            viewedAt: c.flexString(.viewedAt),
            acceptedAt: c.flexString(.acceptedAt),
            declinedAt: c.flexString(.declinedAt),
            deliveredAt: c.flexString(.deliveredAt),
            expiredAt: c.flexString(.expiredAt),
            releasedAt: c.flexString(.releasedAt),
            contactedAt: c.flexString(.contactedAt),
            sendAfter: c.flexString(.sendAfter),
            isSelf: c.flexBool(.isSelf) ?? c.flexBool(.mine) ?? c.flexBool(.selfFlag),
            countHint: c.flexInt(.count)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, recipientId, companyName, company, name, companySlug, slug, clientId, email
        case status, uiStatus, priceSek, priceShown, price, billable, free, freeLead, freeN, tier
        case offeredAt, viewedAt, acceptedAt, declinedAt, deliveredAt, expiredAt, releasedAt, contactedAt, sendAfter
        case isSelf, mine, count
        case selfFlag = "self"
    }
}

enum CardKind: String, Hashable {
    case exclusive, marketplace, unrouted
}

struct Lead: Decodable, Hashable, Identifiable {
    var id: String
    var at: String?
    var clientId: String?
    var client: String?
    var domain: String?
    var siteName: String?
    var source: String?
    var legacyKind: String?
    var cardKindRaw: String?
    var vertical: String?
    var name: String?
    var phone: String?
    var email: String?
    var message: String?
    var notes: String?
    var status: String?
    var marketStatus: String?
    var wonValueSek: Double?
    var wonCompletion: String?
    var followUpDate: String?
    var isTest: Bool?
    var isDuplicate: Bool?
    var badLead: Bool?
    var missed: Bool?
    var durationS: Double?
    var service: String?
    var location: String?
    var detailText: String?
    var slots: LeadSlots?
    var priceSek: Double?
    var offeredCount: Int?
    var acceptedCount: Int?
    var billableCount: Int?
    var freeCount: Int?
    var queuedCount: Int?
    var billing: LeadBilling?
    var assignment: String?
    var leadStatus: String?
    var calculatorTeaser: String?
    var visibility: String?
    var offerStatus: String?
    var slotsLeft: Int?
    var otherOfferedCount: Int?
    var masterExternalId: String?
    var recipientsSummary: RecipientsSummary?
    var inlineRecipients: [LeadRecipient]?
    var contactVisible: Bool?
    var contactHidden: Bool?
    var viewerRole: String?
    var viewerClientId: String?
    var ownOfferStatus: String?
    var acceptedByViewer: Bool?
    var billingNote: String?
    var timing: String?
    var freeLead: Bool?
    var billable: Bool?

    var date: Date? { Fmt.parse(at) }
    var cardKind: CardKind? { cardKindRaw.flatMap(CardKind.init(rawValue:)) }
    var leadKind: LeadKind {
        if let legacyKind, let kind = LeadKind(rawValue: legacyKind) { return kind }
        if missed == true { return .missed }
        switch source {
        case "telavox": return .call
        case "phone": return .phone
        default: return .form
        }
    }
    var isTestLead: Bool { isTest == true }
    var isUnassigned: Bool {
        if assignment == "unassigned" { return true }
        if assignment == "assigned" { return false }
        if cardKind == .marketplace || cardKind == .unrouted { return false }
        guard let id = clientId?.nilIfBlank else { return true }
        return id == "orphaned" || id == "personal"
    }
    var isAdminViewer: Bool {
        let role = (viewerRole ?? "admin").lowercased()
        return role != "client" && role != "buyer"
    }
    /// Homeowner contact is admin-only, or the buyer who accepted.
    var contactIsMasked: Bool {
        if visibility == "teaser" { return true }
        if contactHidden == true { return true }
        if contactVisible == false { return true }
        if isAdminViewer && visibility == nil { return false }
        if visibility == "accepted" || visibility == "exclusive" { return false }
        if acceptedByViewer == true { return false }
        switch (ownOfferStatus ?? offerStatus ?? "").lowercased() {
        case "accepted", "won", "delivered": return false
        default: return !isAdminViewer
        }
    }
    var title: String {
        if contactIsMasked == false, let n = name?.nilIfBlank { return n }
        if let s = service?.nilIfBlank { return s }
        if contactIsMasked == false, let p = phone?.nilIfBlank { return p }
        if contactIsMasked == false, let e = email?.nilIfBlank { return e }
        if let site = siteName?.nilIfBlank { return site }
        return leadKind == .form ? "Form lead" : "Unknown caller"
    }
    var hasCardMetadata: Bool {
        cardKindRaw != nil || marketStatus != nil || priceSek != nil || offeredCount != nil || acceptedCount != nil || recipientsSummary != nil || inlineRecipients != nil
    }

    var inferredService: String? {
        if let service = service?.nilIfBlank { return service }
        return messageValue(for: ["tjänst", "tjanst", "service", "jobb", "ärende", "arende"])
    }

    var inferredLocation: String? {
        if let location = location?.nilIfBlank { return location }
        return messageValue(for: ["kommun", "ort", "stad", "postort", "city", "adress", "address"])
    }

    func accepted(since start: Date) -> Bool {
        for peek in recipientsSummary?.accepted ?? [] {
            if let d = Fmt.parse(peek.at), d >= start { return true }
        }
        for row in inlineRecipients ?? [] where row.displayStatus == "accepted" {
            if let d = Fmt.parse(row.acceptedAt) ?? Fmt.parse(row.offeredAt), d >= start { return true }
        }
        return false
    }

    func overlaying(_ newer: Lead) -> Lead {
        var base = self
        func pick(_ old: String?, _ new: String?) -> String? { new?.nilIfBlank ?? old }
        base.at = pick(base.at, newer.at)
        base.clientId = pick(base.clientId, newer.clientId)
        base.client = pick(base.client, newer.client)
        base.domain = pick(base.domain, newer.domain)
        base.siteName = pick(base.siteName, newer.siteName)
        base.source = pick(base.source, newer.source)
        base.legacyKind = newer.legacyKind ?? base.legacyKind
        base.cardKindRaw = newer.cardKindRaw ?? base.cardKindRaw
        base.vertical = pick(base.vertical, newer.vertical)
        base.notes = pick(base.notes, newer.notes)
        base.status = pick(base.status, newer.status)
        base.marketStatus = pick(base.marketStatus, newer.marketStatus)
        base.wonValueSek = newer.wonValueSek ?? base.wonValueSek
        base.wonCompletion = pick(base.wonCompletion, newer.wonCompletion)
        base.followUpDate = pick(base.followUpDate, newer.followUpDate)
        base.isTest = newer.isTest ?? base.isTest
        base.isDuplicate = newer.isDuplicate ?? base.isDuplicate
        base.badLead = newer.badLead ?? base.badLead
        base.missed = newer.missed ?? base.missed
        base.durationS = newer.durationS ?? base.durationS
        base.service = pick(base.service, newer.service)
        base.location = pick(base.location, newer.location)
        base.detailText = pick(base.detailText, newer.detailText)
        base.slots = newer.slots ?? base.slots
        base.priceSek = newer.priceSek ?? base.priceSek
        base.offeredCount = newer.offeredCount ?? base.offeredCount
        base.acceptedCount = newer.acceptedCount ?? base.acceptedCount
        base.billableCount = newer.billableCount ?? base.billableCount
        base.freeCount = newer.freeCount ?? base.freeCount
        base.queuedCount = newer.queuedCount ?? base.queuedCount
        base.billing = newer.billing ?? base.billing
        base.assignment = pick(base.assignment, newer.assignment)
        base.leadStatus = pick(base.leadStatus, newer.leadStatus)
        base.calculatorTeaser = pick(base.calculatorTeaser, newer.calculatorTeaser)
        base.visibility = pick(base.visibility, newer.visibility)
        base.offerStatus = pick(base.offerStatus, newer.offerStatus)
        base.slotsLeft = newer.slotsLeft ?? base.slotsLeft
        base.otherOfferedCount = newer.otherOfferedCount ?? base.otherOfferedCount
        base.masterExternalId = pick(base.masterExternalId, newer.masterExternalId)
        base.recipientsSummary = newer.recipientsSummary ?? base.recipientsSummary
        if let rows = newer.inlineRecipients, !rows.isEmpty { base.inlineRecipients = rows }
        base.contactVisible = newer.contactVisible ?? base.contactVisible
        base.contactHidden = newer.contactHidden ?? base.contactHidden
        base.viewerRole = pick(base.viewerRole, newer.viewerRole)
        base.viewerClientId = pick(base.viewerClientId, newer.viewerClientId)
        base.ownOfferStatus = pick(base.ownOfferStatus, newer.ownOfferStatus)
        base.acceptedByViewer = newer.acceptedByViewer ?? base.acceptedByViewer
        base.billingNote = pick(base.billingNote, newer.billingNote)
        base.timing = pick(base.timing, newer.timing)
        base.freeLead = newer.freeLead ?? base.freeLead
        base.billable = newer.billable ?? base.billable
        if newer.contactIsMasked {
            base.name = nil
            base.phone = nil
            base.email = nil
            base.message = nil
            base.contactHidden = true
        } else {
            base.name = pick(base.name, newer.name)
            base.phone = pick(base.phone, newer.phone)
            base.email = pick(base.email, newer.email)
            base.message = pick(base.message, newer.message)
        }
        return base
    }

    func syntheticRecipients() -> [LeadRecipient] {
        var rows: [LeadRecipient] = []
        for (index, peek) in (recipientsSummary?.accepted ?? []).enumerated() {
            rows.append(LeadRecipient(storedId: "accepted-\(index)", companyName: peek.name, status: "accepted", priceSek: peek.priceSek ?? priceSek, billable: peek.billable, free: peek.free, acceptedAt: peek.at))
        }
        func add(count: Int, names: [String], status: String) {
            let pending = names.filter { name in !rows.contains { $0.companyName == name && $0.displayStatus == "accepted" } }
            if !pending.isEmpty {
                for (index, name) in pending.enumerated() {
                    rows.append(LeadRecipient(storedId: "\(status)-\(index)", companyName: name, status: status, priceSek: priceSek))
                }
            } else if count > 0 {
                rows.append(LeadRecipient(storedId: "count-\(status)", status: status, priceSek: priceSek, countHint: count))
            }
        }
        add(count: recipientsSummary?.counts.offered ?? offeredCount ?? 0, names: recipientsSummary?.offeredNames ?? [], status: "offered")
        add(count: recipientsSummary?.counts.queued ?? queuedCount ?? slots?.queued ?? 0, names: recipientsSummary?.queuedNames ?? [], status: "queued")
        add(count: recipientsSummary?.counts.declined ?? 0, names: recipientsSummary?.declinedNames ?? [], status: "declined")
        if rows.isEmpty, !isUnassigned, let name = client?.nilIfBlank {
            rows.append(LeadRecipient(
                storedId: "delivered-\(clientId ?? name)",
                companyName: name,
                clientId: clientId,
                status: "delivered",
                priceSek: priceSek,
                billable: billable ?? ((billableCount ?? 0) > 0 ? true : nil),
                free: freeLead ?? ((freeCount ?? 0) > 0 ? true : nil),
                deliveredAt: at,
                sendAfter: at
            ))
        }
        return rows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = c.flexString(.id) ?? c.flexString(.cardId)
        guard let id, !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "lead has no id"))
        }
        self.id = id
        at = c.flexString(.at) ?? c.flexString(.submittedAt)
        clientId = c.flexString(.clientId)
        client = c.flexString(.client) ?? c.flexString(.clientName)
        let siteValue = c.flexString(.site)
        domain = c.flexString(.domain)
        if domain == nil, let siteValue, siteValue.contains(".") { domain = siteValue }
        siteName = c.flexString(.siteName)
        if siteName == nil, let siteValue, !siteValue.contains(".") { siteName = siteValue }
        source = c.flexString(.source)
        let kindRaw = c.flexString(.kind)
        if let kindRaw, LeadKind(rawValue: kindRaw) != nil {
            legacyKind = kindRaw
            cardKindRaw = c.flexString(.cardKind)
        } else {
            cardKindRaw = kindRaw ?? c.flexString(.cardKind)
            legacyKind = c.flexString(.leadKind)
        }
        vertical = c.flexString(.vertical)
        name = c.flexString(.name)
        phone = c.flexString(.phone)
        email = c.flexString(.email)
        message = c.flexString(.message)
        notes = c.flexString(.notes)
        leadStatus = c.flexString(.leadStatus)
        marketStatus = c.flexString(.marketStatus)
        wonValueSek = c.flexDouble(.wonValueSek)
        wonCompletion = c.flexString(.wonCompletion)
        if let display = c.flexString(.status) {
            status = display
        } else {
            status = leadStatus
            if status == "won" {
                if wonCompletion == "completed" { status = "won_completed" }
                else if wonCompletion == "unfinished" { status = "won_unfinished" }
            }
        }
        followUpDate = c.flexString(.followUpDate)
        isTest = c.flexBool(.isTest) ?? c.flexBool(.test)
        isDuplicate = c.flexBool(.isDuplicate)
        badLead = c.flexBool(.badLead) ?? c.flexBool(.junk)
        missed = c.flexBool(.callMissed) ?? c.flexBool(.missed)
        durationS = c.flexDouble(.callDurationS) ?? c.flexDouble(.durationS) ?? c.flexDouble(.duration)
        service = c.flexString(.service)
        location = c.flexString(.location)
        detailText = c.flexString(.detailText)
        slots = try? c.decode(LeadSlots.self, forKey: .slots)
        if slots == nil {
            let max = c.flexInt(.maxSlots)
            let won = c.flexInt(.slotsWon)
            if max != nil || won != nil {
                slots = LeadSlots(max: max, won: won, offered: nil, queued: nil)
            }
        }
        priceSek = c.flexDouble(.priceSek) ?? c.flexDouble(.price) ?? c.flexDouble(.billingRate)
        offeredCount = c.flexInt(.offeredCount)
        acceptedCount = c.flexInt(.acceptedCount)
        billableCount = c.flexInt(.billableCount)
        freeCount = c.flexInt(.freeCount)
        queuedCount = c.flexInt(.queuedCount)
        billing = try? c.decode(LeadBilling.self, forKey: .billing)
        assignment = c.flexString(.assignment)
        calculatorTeaser = c.flexString(.calculatorTeaser)
        visibility = c.flexString(.visibility)
        offerStatus = c.flexString(.offerStatus)
        slotsLeft = c.flexInt(.slotsLeft)
        otherOfferedCount = c.flexInt(.otherOfferedCount)
        masterExternalId = c.flexString(.masterExternalId)
        recipientsSummary = try? c.decode(RecipientsSummary.self, forKey: .recipientsSummary)
        inlineRecipients = nil
        if let wrapped = try? c.decode([Soft<LeadRecipient>].self, forKey: .recipients) {
            let rows = wrapped.compactMap(\.value)
            if !rows.isEmpty { inlineRecipients = rows }
        }
        contactVisible = c.flexBool(.contactVisible)
        contactHidden = c.flexBool(.contactHidden)
        viewerRole = c.flexString(.viewer) ?? c.flexString(.role)
        viewerClientId = c.flexString(.viewerClientId)
        ownOfferStatus = c.flexString(.ownOfferStatus)
        acceptedByViewer = c.flexBool(.acceptedByViewer)
        billingNote = c.flexString(.billingNote) ?? c.flexString(.billingExplanation) ?? c.flexString(.billedFreeExplanation)
        timing = c.flexString(.timing) ?? c.flexString(.when) ?? c.flexString(.nar)
        freeLead = c.flexBool(.freeLead)
        billable = c.flexBool(.billable)
        if let raw = try? c.decode(RawHints.self, forKey: .rawData) {
            if missed == nil { missed = raw.missed }
            if isTest == nil { isTest = raw.test }
            if service == nil { service = raw.service ?? raw.jobbLabel ?? raw.jobb }
            if location == nil { location = raw.city ?? raw.kommun ?? raw.callerCity ?? raw.lan }
            if vertical == nil { vertical = raw.vertical }
            if freeLead == nil { freeLead = raw.freeLead }
            if timing == nil { timing = raw.nar ?? raw.timing }
            if durationS == nil { durationS = raw.durationS }
        }
        if offeredCount == nil { offeredCount = recipientsSummary?.counts.offered }
        if acceptedCount == nil, recipientsSummary != nil {
            acceptedCount = recipientsSummary?.accepted.count
        }
    }

    private func messageValue(for keys: [String]) -> String? {
        for lineSub in (message ?? "").split(separator: "\n") {
            let line = String(lineSub)
            let lower = line.lowercased()
            for key in keys where lower.hasPrefix(key + ":") {
                let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, cardId, at, submittedAt, clientId, client, clientName, domain, site, siteName, source
        case kind, cardKind, leadKind, vertical, name, phone, email, message, notes
        case status, leadStatus, marketStatus, wonValueSek, wonCompletion, followUpDate
        case isTest, test, isDuplicate, badLead, junk, missed, callMissed, durationS, callDurationS, duration
        case service, location, slots, maxSlots, slotsWon
        case detailText = "description"
        case priceSek, price, billingRate, offeredCount, acceptedCount, billableCount, freeCount, queuedCount
        case billing, assignment, calculatorTeaser, visibility, offerStatus, slotsLeft, otherOfferedCount
        case masterExternalId, recipientsSummary, recipients
        case contactVisible, contactHidden, viewer, role, viewerClientId, ownOfferStatus, acceptedByViewer
        case billingNote, billingExplanation, billedFreeExplanation, timing, when, nar, freeLead, billable, rawData
    }
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

private struct RawHints: Decodable {
    var missed: Bool?
    var test: Bool?
    var service: String?
    var jobb: String?
    var jobbLabel: String?
    var city: String?
    var kommun: String?
    var lan: String?
    var vertical: String?
    var freeLead: Bool?
    var nar: String?
    var timing: String?
    var callerCity: String?
    var durationS: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        missed = c.flexBool(.missed)
        test = c.flexBool(.test)
        service = c.flexString(.service)
        jobb = c.flexString(.jobb)
        jobbLabel = c.flexString(.jobbLabel)
        city = c.flexString(.city)
        kommun = c.flexString(.kommun)
        lan = c.flexString(.lan)
        vertical = c.flexString(.vertical)
        freeLead = c.flexBool(.freeLead)
        nar = c.flexString(.nar)
        timing = c.flexString(.timing)
        callerCity = c.flexString(.callerCity)
        durationS = c.flexDouble(.durationS)
    }

    private enum CodingKeys: String, CodingKey {
        case missed, test, service, jobb, jobbLabel, city, kommun, lan, vertical, freeLead, nar, timing, callerCity, durationS
    }
}

private struct Soft<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
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
    var nilIfBlank: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
}

extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String? {
        guard contains(key) else { return nil }
        if let v = try? decode(String.self, forKey: key) { return v.nilIfBlank }
        if let v = try? decode(Int.self, forKey: key) { return String(v) }
        if let v = try? decode(Double.self, forKey: key) {
            if v.rounded() == v { return String(Int(v)) }
            return String(v)
        }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        guard contains(key) else { return nil }
        if let v = try? decode(Double.self, forKey: key) { return v }
        if let v = try? decode(Int.self, forKey: key) { return Double(v) }
        if let v = try? decode(String.self, forKey: key) {
            return Double(v.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
        }
        return nil
    }

    func flexInt(_ key: Key) -> Int? {
        guard contains(key) else { return nil }
        if let v = try? decode(Int.self, forKey: key) { return v }
        if let v = try? decode(Double.self, forKey: key) { return Int(v.rounded()) }
        if let v = try? decode(String.self, forKey: key) {
            let digits = v.filter { $0.isNumber || $0 == "-" }
            return Int(digits)
        }
        return nil
    }

    func flexBool(_ key: Key) -> Bool? {
        guard contains(key) else { return nil }
        if let v = try? decode(Bool.self, forKey: key) { return v }
        if let v = try? decode(Int.self, forKey: key) { return v != 0 }
        if let v = try? decode(String.self, forKey: key) {
            switch v.trimmed.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}
