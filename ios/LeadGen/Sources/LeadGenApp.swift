import SwiftUI

@main
struct LeadGenApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
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
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.25), value: store.isLocked)
        .animation(.easeInOut(duration: 0.25), value: store.session)
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            LeadsTab()
                .tabItem { Label("Leads", systemImage: "tray.full.fill") }
                .tag(AppTab.leads)
            ClientsView()
                .tabItem { Label("Clients", systemImage: "person.2.fill") }
                .tag(AppTab.clients)
            MoneyView()
                .tabItem { Label("Money", systemImage: "creditcard.fill") }
                .tag(AppTab.money)
            SitesView()
                .tabItem { Label("Sites", systemImage: "globe") }
                .tag(AppTab.sites)
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
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            AppMark(size: 72)
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}
