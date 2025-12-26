//
//  ContentView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI

struct ContentView: View {
    enum Tab: Hashable { case today, focus }

    @State private var selectedTab: Tab = .today

    var body: some View {
        TabView(selection: $selectedTab) {

            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            FocusSessionFlowView()
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(Tab.focus)
        }
    }
}

#Preview {
    ContentView()
}
