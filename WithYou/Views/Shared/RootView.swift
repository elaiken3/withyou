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

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            
            FocusSessionFlowView()
                .tabItem { Label("Focus", systemImage: "timer") }

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }

            QuickAddView()
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
        }
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
        }
    }
}

