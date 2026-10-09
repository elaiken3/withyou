//
//  DailyCheckInSection.swift
//  WithYou
//

import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Settings rows for the optional daily check-in (see `DailyCheckIn`).
/// A `Section`, for use inside a `Form` or `List`.
struct DailyCheckInSection: View {
    // Keys match `DailyCheckIn.enabledKey` / `DailyCheckIn.minutesKey`.
    @AppStorage("dailyCheckInEnabled") private var isOn: Bool = false
    @AppStorage("dailyCheckInMinutes") private var minutes: Int = 540

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// True when the check-in is on but notifications are off for WithYou.
    @State private var notificationsOff = false

    var body: some View {
        Section {
            // Row-level modifiers: the toggle row is always there.
            Toggle("Daily check-in", isOn: $isOn)
                .listRowBackground(Color.appSurface)
                .onChange(of: isOn) { _, newValue in
                    if newValue {
                        Task {
                            let allowed = await DailyCheckIn.turnedOn()
                            notificationsOff = !allowed
                        }
                    } else {
                        notificationsOff = false
                        DailyCheckIn.reschedule()
                    }
                }
                .onChange(of: minutes) { _, _ in
                    DailyCheckIn.reschedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Back from iOS Settings, notifications may be on now.
                    if phase == .active {
                        Task { await refreshPermissionState() }
                    }
                }
                .task {
                    await refreshPermissionState()
                }

            if isOn {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .accessibilityLabel("Check-in time")
                    .listRowBackground(Color.appSurface)

                if notificationsOff {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications are off for WithYou, so the check-in can’t show up yet.")
                            .font(.subheadline)
                            .foregroundStyle(.appSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
        } header: {
            Text("Check-in")
        } footer: {
            Text("One quiet notification a day at the time you choose, to look at Today if you want to. Skipping it is fine; nothing piles up.")
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                DailyCheckIn.pickerDate(forMinutes: minutes, on: Date(), calendar: .current)
            },
            set: { newValue in
                minutes = DailyCheckIn.minutesAfterMidnight(of: newValue, calendar: .current)
            }
        )
    }

    /// Notices when notifications were turned off in iOS Settings after the check-in was on.
    private func refreshPermissionState() async {
        guard isOn else {
            notificationsOff = false
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus == .denied
    }
}
