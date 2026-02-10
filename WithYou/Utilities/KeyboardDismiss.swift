//
//  KeyboardDismiss.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import SwiftUI

extension View {
    func dismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        })
    }
}
