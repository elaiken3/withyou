//
//  ProfilesView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct ProfilesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]
    @Query private var appStates: [AppState]

    @State private var newName: String = ""

    private var appState: AppState {
        ProfileStore.appState(in: context)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("New profile name", text: $newName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let p = UserProfile(name: name)
                        context.insert(p)
                        if appState.activeProfileId == nil {
                            appState.activeProfileId = p.id
                        }
                        try? context.save()
                        newName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                List {
                    ForEach(profiles) { p in
                        NavigationLink {
                            ProfileDetailView(profile: p)
                        } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if appState.activeProfileId == p.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .swipeActions {
                            Button("Use") {
                                appState.activeProfileId = p.id
                                try? context.save()
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(profiles[i]) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Profiles")
        }
    }
}

private struct ProfileDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    // TODO: replace with your real URL
    private let howToURL = URL(string: "https://wearewithyou.app/how-to/")!

    @State private var isRegisteringPush = false

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $profile.name)
                Picker("Tone", selection: $profile.toneRaw) {
                    Text("Gentle").tag(ReminderTone.gentle.rawValue)
                    Text("Firm").tag(ReminderTone.firm.rawValue)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { profile.colorSchemeRaw },
                    set: { newValue in
                        Haptics.tap()
                        profile.colorSchemeRaw = newValue
                        try? context.save()
                        NotificationCenter.default.post(name: .appearancePreferenceChanged, object: nil)
                        Haptics.success()
                    }
                )) {
                    Text("System").tag(AppColorScheme.system.rawValue)
                    Text("Light").tag(AppColorScheme.light.rawValue)
                    Text("Dark").tag(AppColorScheme.dark.rawValue)
                }
                .pickerStyle(.segmented)
            }

            Section("Defaults") {
                Stepper("Morning hour: \(profile.morningHour)", value: $profile.morningHour, in: 5...12)
                Stepper("Afternoon hour: \(profile.afternoonHour)", value: $profile.afternoonHour, in: 12...17)
                Stepper("Evening hour: \(profile.eveningHour)", value: $profile.eveningHour, in: 17...23)
                Stepper("Focus minutes: \(profile.defaultFocusMinutes)", value: $profile.defaultFocusMinutes, in: 10...90, step: 5)
            }

            Section("Refocus") {
                TextField("Mantra", text: $profile.defaultMantra)
            }

            Section("Capture routing") {
                Toggle("Route capture to Focus Dump during focus", isOn: $profile.routeSiriToFocusDumpWhenActive)
            }

            Section("Help") {
                Link(destination: howToURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                        Text("How to use With You")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
#if DEBUG
            Section("Debug") {
                Button {
                    isRegisteringPush = true
                    Task {
                        if let token = DeviceRegistration.cachedToken() {
                            await DeviceRegistration.registerIfNeeded(token: token, force: true)
                        }
                        isRegisteringPush = false
                    }
                } label: {
                    HStack {
                        Text(isRegisteringPush ? "Registering…" : "Re-register push token")
                        Spacer()
                        if isRegisteringPush {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRegisteringPush)
            }
#endif
        }
        .navigationTitle(profile.name)
        .onDisappear { try? context.save() }
    }
}
