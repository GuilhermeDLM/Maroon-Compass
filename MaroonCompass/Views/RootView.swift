import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store

        TabView(selection: $store.selectedTab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack { ScheduleView() }
            }
            Tab("Plan", systemImage: "calendar.badge.plus", value: AppTab.plan) {
                NavigationStack { PersonalPlanView() }
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapExploreView()
            }
            Tab("Saved", systemImage: "bookmark.fill", value: AppTab.saved) {
                NavigationStack { SavedView() }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .task { await store.loadCampus() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-UIImportSchedule") {
                store.selectedTab = .schedule
            }
            store.applyPendingIntentNavigation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.applyPendingIntentNavigation() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !store.hasCompletedOnboarding },
            set: { if !$0 { store.completeOnboarding() } }
        )) {
            OnboardingView()
                .environment(store)
        }
        .onOpenURL { url in
            switch url.host {
            case "schedule": store.selectedTab = .schedule
            case "plan": store.selectedTab = .plan
            case "map": store.selectedTab = .map
            default: store.selectedTab = .today
            }
        }
    }
}
