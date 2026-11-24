import Foundation
import LocalAuthentication
import Observation
import SwiftUI

enum Session: Equatable { case signedOut, signedIn }

enum AppTab: Hashable { case today, leads, clients, money, sites }

@MainActor
@Observable
final class AppStore {
    var session: Session
    var isLocked: Bool
    var isObscured = false
    var selectedTab: AppTab = .today

    var summary: Summary?
    var leads: [Lead] = []
    var clients: [Client] = []
    var sites: [Site] = []
    var index = LeadIndex()

    var lastUpdated: Date?
    var isRefreshing = false
    var errorMessage: String?
    var loginMessage: String?
    var refreshCount = 0
    var leadDetails: [String: LeadDetailPayload] = [:]
    var leadDetailFailed: Set<String> = []

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var needsAutoUnlock = true
    @ObservationIgnored private var isAuthenticating = false
    @ObservationIgnored private var windowGeneration = 0
    @ObservationIgnored private var windowTask: Task<Void, Never>?

    var hasData: Bool { summary != nil }

    init() {
        let saved = Keychain.read()
        token = saved
        session = saved == nil ? .signedOut : .signedIn
        isLocked = saved != nil
        if saved != nil { loadCache() }
    }

    // MARK: Sign in and out

    func signIn(password: String) async throws {
        let t = try await APIClient(token: nil).login(password: password)
        Keychain.save(t)
        token = t
        loginMessage = nil
        needsAutoUnlock = false
        isLocked = false
        session = .signedIn
        await refresh()
    }

    func signOut(message: String? = nil) {
        Keychain.delete()
        DiskCache.clear()
        windowTask?.cancel()
        windowGeneration += 1
        token = nil
        summary = nil
        leads = []
        index = LeadIndex()
        clients = []
        sites = []
        leadDetails = [:]
        leadDetailFailed = []
        lastUpdated = nil
        errorMessage = nil
        loginMessage = message
        isLocked = false
        selectedTab = .today
        session = .signedOut
    }

    // MARK: Face ID lock

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var biometrySymbol: String {
        switch biometryName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            isObscured = true
            if session == .signedIn {
                isLocked = true
                needsAutoUnlock = true
            }
        case .inactive:
            isObscured = true
        case .active:
            isObscured = false
            if isLocked {
                autoUnlockIfNeeded()
            } else if session == .signedIn, isStale {
                Task { await refresh() }
            }
        @unknown default:
            break
        }
    }

    func autoUnlockIfNeeded() {
        guard isLocked, needsAutoUnlock else { return }
        needsAutoUnlock = false
        Task { await unlock() }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode on the device: nothing to unlock with.
            isLocked = false
            if isStale { await refresh() }
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your lead gen numbers")
            if ok {
                isLocked = false
                if isStale { await refresh() }
            }
        } catch {
            // Cancelled. The lock screen keeps an Unlock button.
        }
    }

    // MARK: Data

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 60
    }

    private func loadCache() {
        let d = APIClient.decoder
        if let data = DiskCache.load("summary"), let s = try? d.decode(Summary.self, from: data) { summary = s }
        if let data = DiskCache.load("leads"), let page = try? d.decode(LeadPage.self, from: data) { leads = Self.deduped(page.leads) }
        if let data = DiskCache.load("clients"), let c = try? d.decode(ClientsResponse.self, from: data) { clients = c.clients ?? [] }
        if let data = DiskCache.load("sites"), let s = try? d.decode(SitesResponse.self, from: data) { sites = s.sites ?? [] }
        index = LeadIndex(leads)
        if let s = summary?.generatedAt { lastUpdated = Fmt.parse(s) }
    }

    private func fetch<T: Decodable>(_ api: APIClient, _ path: String, cacheAs name: String, as type: T.Type) async -> Result<T, Error> {
        do {
            let data = try await api.get(path)
            let value = try APIClient.decoder.decode(T.self, from: data)
            DiskCache.save(data, as: name)
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    func refresh() async {
        guard let token, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        windowTask?.cancel()
        windowGeneration += 1
        let api = APIClient(token: token)
        let leadsPath = Endpoint.path("/api/m/leads", [
            URLQueryItem(name: "days", value: "90"),
            URLQueryItem(name: "per_page", value: "100"),
        ])

        async let s = fetch(api, "/api/m/summary", cacheAs: "summary", as: Summary.self)
        async let l = fetch(api, leadsPath, cacheAs: "leads", as: LeadPage.self)
        async let c = fetch(api, "/api/m/clients", cacheAs: "clients", as: ClientsResponse.self)
        async let st = fetch(api, "/api/m/sites", cacheAs: "sites", as: SitesResponse.self)
        let results = await (s, l, c, st)

        var firstError: Error?
        var more: String?
        withAnimation(.smooth(duration: 0.6)) {
            switch results.0 { case .success(let v): summary = v; case .failure(let e): firstError = firstError ?? e }
            switch results.1 {
            case .success(let page):
                applyLeads(page.leads)
                if page.hasMore, let cursor = page.nextCursor { more = cursor }
            case .failure(let e):
                firstError = firstError ?? e
            }
            switch results.2 { case .success(let v): clients = v.clients ?? []; case .failure(let e): firstError = firstError ?? e }
            switch results.3 { case .success(let v): sites = v.sites ?? []; case .failure(let e): firstError = firstError ?? e }
        }

        if let firstError {
            errorMessage = note(firstError)
            if session == .signedOut { return }
        } else {
            errorMessage = nil
            lastUpdated = Date()
            refreshCount += 1
        }
        if let more, session == .signedIn {
            startLeadWindow(after: more)
        }
    }

    /// Turns a transport or decode failure into a sentence. An expired session signs out.
    @discardableResult
    func note(_ error: Error) -> String {
        if error is CancellationError { return "" }
        if let api = error as? APIError, case .unauthorized = api {
            signOut(message: api.errorDescription)
            return api.errorDescription ?? "Your session expired. Sign in again."
        }
        if let api = error as? APIError, case .server(let code) = api {
            if code == 404 { return "That lead is not on the server." }
            if code == 400 { return "That filter was rejected. Change it and try again." }
            if code == 503 { return "Lead cards are not installed on the server yet." }
        }
        if error is DecodingError {
            return "Some data could not be read. Pull to try again."
        }
        return error.localizedDescription
    }

    func leadPage(_ path: String) async throws -> (LeadPage, Data) {
        let data = try await authorizedData(path)
        return (try APIClient.decoder.decode(LeadPage.self, from: data), data)
    }

    func cachedLeadPage(for key: String) -> LeadPage? {
        guard let rawKey = DiskCache.load("lead-cards-key"),
              String(data: rawKey, encoding: .utf8) == key,
              let data = DiskCache.load("lead-cards"),
              let page = try? APIClient.decoder.decode(LeadPage.self, from: data) else { return nil }
        return page
    }

    func storeLeadPage(_ data: Data, key: String) {
        DiskCache.save(data, as: "lead-cards")
        DiskCache.save(Data(key.utf8), as: "lead-cards-key")
    }

    func loadLeadDetail(_ id: String) async {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        do {
            let data = try await authorizedData("/api/m/leads/\(encoded)")
            let payload = try APIClient.decoder.decode(LeadDetailPayload.self, from: data)
            leadDetails[id] = payload
            leadDetailFailed.remove(id)
        } catch is CancellationError {
            return
        } catch {
            leadDetailFailed.insert(id)
            _ = note(error)
        }
    }

    private func authorizedData(_ path: String) async throws -> Data {
        guard let token else { throw APIError.unauthorized }
        return try await APIClient(token: token).get(path)
    }

    private func applyLeads(_ rows: [Lead]) {
        leads = Self.deduped(rows)
        index = LeadIndex(leads)
    }

    private func mergeLeads(_ rows: [Lead]) {
        applyLeads(leads + rows)
    }

    private static func deduped(_ rows: [Lead]) -> [Lead] {
        var seen = Set<String>()
        var out: [Lead] = []
        let sorted = rows.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for lead in sorted where seen.insert(lead.id).inserted {
            out.append(lead)
        }
        return out
    }

    /// Follows cursors so Today still counts a 90-day window after the list endpoint starts paging.
    private func startLeadWindow(after cursor: String) {
        windowTask?.cancel()
        windowGeneration += 1
        let generation = windowGeneration
        windowTask = Task { await self.fillLeadWindow(cursor: cursor, generation: generation) }
    }

    private func fillLeadWindow(cursor start: String, generation: Int) async {
        var nextCursor: String? = start
        var pages = 0
        while let current = nextCursor, pages < 6, generation == windowGeneration, !Task.isCancelled {
            pages += 1
            let path = Endpoint.path("/api/m/leads", [
                URLQueryItem(name: "days", value: "90"),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "cursor", value: current),
            ])
            do {
                let data = try await authorizedData(path)
                let page = try APIClient.decoder.decode(LeadPage.self, from: data)
                guard generation == windowGeneration, !Task.isCancelled else { return }
                mergeLeads(page.leads)
                if page.hasMore, let next = page.nextCursor, next != current {
                    nextCursor = next
                } else {
                    nextCursor = nil
                }
            } catch {
                return
            }
        }
    }

    // MARK: Lookups

    func client(_ id: String?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.clientId == id }
    }

    func site(_ domain: String?) -> Site? {
        guard let domain else { return nil }
        return sites.first { $0.domain == domain }
    }
}
