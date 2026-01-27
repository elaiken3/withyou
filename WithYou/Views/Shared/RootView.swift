//
//  RootView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedTab: AppTab = .today

    // Drives light/dark/system for the whole app UI
    @State private var preferredScheme: ColorScheme? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tag(AppTab.today)
                .tabItem { Label("Today", systemImage: "sun.max") }

            FocusSessionFlowView(selectedTab: $selectedTab)
                .tag(AppTab.focus)
                .tabItem { Label("Focus", systemImage: "timer") }

            InboxView()
                .tag(AppTab.inbox)
                .tabItem { Label("Inbox", systemImage: "tray") }

            ScheduleView()
                .tag(AppTab.schedule)
                .tabItem { Label("Schedule", systemImage: "calendar") }

            QuickAddView()
                .tag(AppTab.capture)
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
        }
        // ✅ Apply to the whole app UI
        .preferredColorScheme(preferredScheme)
        .onReceive(NotificationCenter.default.publisher(for: .appearancePreferenceChanged)) { _ in
            refreshPreferredScheme()
        }
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            FocusSessionStore.normalizeActiveSessions(in: context)
            refreshPreferredScheme()
        }
        .task {
                    await PushDebug.register()
                }
        // ✅ Re-evaluate periodically when RootView becomes active again (covers “back from settings” cases)
        .onChange(of: selectedTab) { _, _ in
            refreshPreferredScheme()
        }
    }

    private func refreshPreferredScheme() {
        let profile = ProfileStore.activeProfile(in: context)

        // If you implemented profile.colorSchemeRaw + AppColorScheme.preferred:
        preferredScheme = profile?.colorScheme.preferred
    }
}
