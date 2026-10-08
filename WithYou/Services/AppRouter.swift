//
//  AppRouter.swift
//  WithYou
//

import Foundation
import Observation

/// Places the app can be asked to open from outside a view:
/// notification taps/actions, App Intents, and backend deep links.
enum AppRoute: Equatable {
    case today
    case focus
    case inbox
    case schedule
    case capture
    /// Present the 30-second Refocus sheet.
    case refocus
    /// Open Today and present "I'm stuck", optionally starting from a reminder.
    case stuck(reminderId: UUID?)
    /// Open Today and present the edit sheet for a reminder.
    case reminder(UUID)
    /// Start a focus session for a reminder and open the Focus tab.
    case startFocus(reminderId: UUID)
}

/// Hand-off point between non-view code and the view hierarchy.
///
/// Contract:
/// - `RootView` observes `pendingRoute` and handles `.today`, `.focus`, `.inbox`,
///   `.schedule`, `.capture`, `.refocus` and `.startFocus`, calling `consume()`.
/// - For `.stuck` and `.reminder`, `RootView` only switches to the Today tab and leaves
///   the route pending; `TodayView` presents the sheet and calls `consume()`.
/// - Views must also check `pendingRoute` in `onAppear`, because a cold launch from a
///   notification sets the route before any view exists.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var pendingRoute: AppRoute?

    private init() {}

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

    /// Maps backend deep links like `withyou://today` to a route.
    func open(deepLink: String) {
        guard let url = URL(string: deepLink), url.scheme == "withyou" else { return }
        switch url.host {
        case "focus": open(.focus)
        case "inbox": open(.inbox)
        case "schedule": open(.schedule)
        case "capture": open(.capture)
        case "refocus": open(.refocus)
        case "stuck": open(.stuck(reminderId: nil))
        default: open(.today)
        }
    }
}
