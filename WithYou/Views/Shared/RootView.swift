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

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

            FocusSessionFlowView()
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(AppTab.focus)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppTab.inbox)

            QuickAddView()
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
                .tag(AppTab.capture)

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
                .tag(AppTab.profiles)
        }
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            FocusSessionStore.normalizeActiveSessions(in: context)
        }
    }
}
