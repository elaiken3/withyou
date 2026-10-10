//
//  AppRouter.swift
//  WithYou
//

import Foundation
import Observation
import UIKit

/// Places the app can be asked to open from outside a view:
/// notification taps/actions, App Intents, and deep links.
enum AppRoute: Equatable {
    case today
    case focus
    case inbox
    case schedule
    case capture
    /// Present the Refocus breathing sheet (about a minute).
    case refocus
    /// Open Today and present "I'm stuck", optionally starting from a reminder.
    case stuck(reminderId: UUID?)
    /// Open Today and present the edit sheet for a reminder.
    case reminder(UUID)
    /// Start a focus session for a reminder and open the Focus tab.
    case startFocus(reminderId: UUID)
    /// Present voice capture (the mic opens right away).
    case voiceCapture
}

/// Hand-off point between non-view code and the view hierarchy.
///
/// Contract:
/// - `RootView` observes `pendingRoute` and handles `.today`, `.focus`, `.inbox`,
///   `.schedule`, `.capture`, `.refocus`, `.startFocus` and `.voiceCapture`, calling `consume()`.
/// - For `.stuck` and `.reminder`, `RootView` only switches to the Today tab and leaves
///   the route pending; `TodayView` presents the sheet and calls `consume()`.
/// - Views must also check `pendingRoute` in `onAppear`, because a cold launch from a
///   notification sets the route before any view exists.
/// - Only one sheet can be up at a time, and views present their own. A route that needs a
///   sheet checks `isSheetUp`; if something is up it calls `closeAllSheets()` and presents a
///   moment later. Every view that presents sheets observes `closeSheetsRequest` and closes them.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var pendingRoute: AppRoute?

    /// Bumped by `closeAllSheets()`. Views that present sheets close them when it changes.
    private(set) var closeSheetsRequest = 0

    /// True while voice capture is on screen (from a route or from Capture). Another voice
    /// capture request leaves it, and the words in it, alone.
    @ObservationIgnored var isVoiceCaptureOpen = false

    private init() {}

    /// Asks every view to close the sheets it presents, so a route can show its own.
    func closeAllSheets() {
        closeSheetsRequest += 1
    }

    /// True while a sheet or dialog is up anywhere in the app. Views present their own sheets,
    /// so this asks the window instead of keeping count view by view.
    var isSheetUp: Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.rootViewController?.presentedViewController != nil {
                return true
            }
        }
        return false
    }

    func open(_ route: AppRoute) {
        pendingRoute = route
    }

    /// Returns the pending route and clears it.
    @discardableResult
    func consume() -> AppRoute? {
        let route = pendingRoute
        pendingRoute = nil
        return route
    }

    /// Maps deep links like `withyou://today` or `withyou://voice` to a route.
    func open(deepLink: String) {
        guard let url = URL(string: deepLink), url.scheme == "withyou" else { return }
        switch url.host {
        case "focus": open(.focus)
        case "inbox": open(.inbox)
        case "schedule": open(.schedule)
        case "capture": open(.capture)
        case "refocus": open(.refocus)
        case "stuck": open(.stuck(reminderId: nil))
        case "voice": open(.voiceCapture)
        default: open(.today)
        }
    }
}
