//
//  AppTab.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/26/25.
//

import Foundation

enum AppTab: Hashable, CaseIterable {
    case today, focus, schedule, inbox, capture

    static let ordered: [AppTab] = [.today, .focus, .inbox, .schedule, .capture]

    var title: String {
        switch self {
        case .today: return "Today"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .schedule: return "Schedule"
        case .capture: return "Capture"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .focus: return "timer"
        case .inbox: return "tray"
        case .schedule: return "calendar"
        case .capture: return "plus.circle.fill"
        }
    }
}
