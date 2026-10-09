//
//  AppearanceNotifications.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/2/26.
//

import Foundation

extension Notification.Name {
    /// Legacy signal posted when the appearance setting changes.
    ///
    /// `RootView` no longer needs it: it reads the active profile's color scheme through
    /// `@Query`, so the app updates as soon as the profile changes. The name stays so
    /// existing posters keep compiling; posting it is harmless.
    static let appearancePreferenceChanged = Notification.Name("appearancePreferenceChanged")
}
