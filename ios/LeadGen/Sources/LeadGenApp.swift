import SwiftUI

@main
struct LeadGenApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.violet)
        }
        .onChange(of: scenePhase) { _, phase in
            store.handleScenePhase(phase)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            switch store.session {
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
            if store.session == .signedIn && store.isLocked {
                LockView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if store.isObscured && store.session == .signedIn {
                PrivacyCover()
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.35), value: store.isLocked)
        .animation(.smooth(duration: 0.45), value: store.session)
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Today", systemImage: "square.grid.2x2.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Leads", systemImage: "person.crop.rectangle.stack.fill", value: AppTab.leads) {
                LeadsTab()
            }
            .badge(store.leadsToday)
            Tab("Clients", systemImage: "building.2.fill", value: AppTab.clients) {
                ClientsView()
            }
            Tab("Money", systemImage: "chart.bar.xaxis.ascending", value: AppTab.money) {
                MoneyView()
            }
            Tab("Sites", systemImage: "globe.europe.africa.fill", value: AppTab.sites) {
                SitesView()
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedTab)
        .sensoryFeedback(.success, trigger: store.refreshCount)
        .task {
            if store.isStale && !store.isLocked { await store.refresh() }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            AppMark(size: 84)
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 80

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: Theme.deepViolet.opacity(0.45), radius: size * 0.2, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// Slowly drifting brand gradient behind sign in and lock.
struct BrandBackdrop: View {
    @State private var t: Float = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let s = Float(ctx.date.timeIntervalSinceReferenceDate)
            let a = 0.12 * sin(s * 0.35)
            let b = 0.12 * cos(s * 0.28)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + a, 0.5 + b], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.20), Color(red: 0.20, green: 0.12, blue: 0.55), Color(red: 0.42, green: 0.32, blue: 0.95),
                    Color(red: 0.10, green: 0.06, blue: 0.32), Color(red: 0.32, green: 0.24, blue: 0.85), Color(red: 0.55, green: 0.42, blue: 1.0),
                    Color(red: 0.04, green: 0.03, blue: 0.14), Color(red: 0.12, green: 0.08, blue: 0.38), Color(red: 0.25, green: 0.18, blue: 0.70),
                ]
            )
        }
        .ignoresSafeArea()
    }
}
