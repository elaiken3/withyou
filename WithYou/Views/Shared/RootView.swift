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
            ForEach(AppTab.ordered, id: \.self) { tab in
                tabView(for: tab)
                    .tag(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            }
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

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(selectedTab: $selectedTab)
        case .focus:
            FocusSessionFlowView(selectedTab: $selectedTab)
        case .inbox:
            InboxView()
        case .schedule:
            ScheduleView()
        case .capture:
            QuickAddView()
        }
    }
}
