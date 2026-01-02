//
//  AppScreen.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/2/26.
//

import SwiftUI

struct AppScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            content
        }
    }
}
