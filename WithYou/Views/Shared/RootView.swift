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
                .tag(AppTab.today)
                .tabItem { Label("Today", systemImage: "sun.max") }

            FocusSessionFlowView()
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
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            FocusSessionStore.normalizeActiveSessions(in: context)
        }
    }
}
