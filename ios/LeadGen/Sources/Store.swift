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

    var lastUpdated: Date?
    var isRefreshing = false
    var errorMessage: String?
    var loginMessage: String?
    var refreshCount = 0

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var needsAutoUnlock = true
    @ObservationIgnored private var isAuthenticating = false

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
        token = nil
        summary = nil
        leads = []
        clients = []
        sites = []
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
        if let data = DiskCache.load("leads"), let l = try? d.decode(LeadsResponse.self, from: data) { leads = l.leads ?? [] }
        if let data = DiskCache.load("clients"), let c = try? d.decode(ClientsResponse.self, from: data) { clients = c.clients ?? [] }
        if let data = DiskCache.load("sites"), let s = try? d.decode(SitesResponse.self, from: data) { sites = s.sites ?? [] }
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
        let api = APIClient(token: token)

        async let s = fetch(api, "/api/m/summary", cacheAs: "summary", as: Summary.self)
        async let l = fetch(api, "/api/m/leads?days=90", cacheAs: "leads", as: LeadsResponse.self)
        async let c = fetch(api, "/api/m/clients", cacheAs: "clients", as: ClientsResponse.self)
        async let st = fetch(api, "/api/m/sites", cacheAs: "sites", as: SitesResponse.self)
        let results = await (s, l, c, st)

        var firstError: Error?
        switch results.0 { case .success(let v): summary = v; case .failure(let e): firstError = firstError ?? e }
        switch results.1 { case .success(let v): leads = v.leads ?? []; case .failure(let e): firstError = firstError ?? e }
        switch results.2 { case .success(let v): clients = v.clients ?? []; case .failure(let e): firstError = firstError ?? e }
        switch results.3 { case .success(let v): sites = v.sites ?? []; case .failure(let e): firstError = firstError ?? e }

        if let firstError {
            if let apiError = firstError as? APIError, case .unauthorized = apiError {
                signOut(message: APIError.unauthorized.errorDescription)
                return
            }
            if firstError is DecodingError {
                errorMessage = "Some data could not be read. Pull to try again."
            } else {
                errorMessage = firstError.localizedDescription
            }
        } else {
            errorMessage = nil
            lastUpdated = Date()
            refreshCount += 1
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

    /// Daily lead counts for the last `days` days from the local lead list.
    func daily(days: Int, matching: (Lead) -> Bool) -> [ChartPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var forms: [Date: Int] = [:]
        var calls: [Date: Int] = [:]
        for lead in leads where !lead.isTestLead && matching(lead) {
            guard let d = lead.date else { continue }
            let day = cal.startOfDay(for: d)
            if lead.leadKind.isCall { calls[day, default: 0] += 1 } else { forms[day, default: 0] += 1 }
        }
        var out: [ChartPoint] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            out.append(ChartPoint(day: day, series: "Forms", count: forms[day] ?? 0))
            out.append(ChartPoint(day: day, series: "Calls", count: calls[day] ?? 0))
        }
        return out
    }
}

struct ChartPoint: Identifiable, Hashable {
    var day: Date
    var series: String
    var count: Int
    var id: String { "\(day.timeIntervalSince1970)-\(series)" }
}
