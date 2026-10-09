//
//  KeyboardDismiss.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import SwiftUI
import UIKit

extension View {
    /// Lowers the keyboard when the person taps outside a text field.
    /// Uses a simultaneous gesture so buttons and rows underneath still receive their taps.
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
