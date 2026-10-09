//
//  ProfilesView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Settings: profiles, app-wide Focus & Refocus options, the daily check-in, AI help,
/// privacy and help.
///
/// Has no NavigationStack of its own; callers wrap it: `NavigationStack { ProfilesView() }`.
struct ProfilesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]
    @Query private var appStates: [AppState]

    @AppStorage("keepScreenAwakeDuringFocus") private var keepScreenAwake: Bool = true
    @AppStorage("hapticBreathing") private var hapticBreathing: Bool = true
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false

    @State private var newName: String = ""
    @State private var profilePendingDeletion: UserProfile? = nil

    @State private var showWelcome = false

    private static let privacyURL = URL(string: "https://wearewithyou.app/privacy/")!
    private static let supportURL = URL(string: "https://wearewithyou.app/support/")!
    private static let howToURL = URL(string: "https://wearewithyou.app/how-to/")!

    private var activeProfileId: UUID? {
        appStates.first?.activeProfileId
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            profilesSection
            addProfileSection
            focusSection
            DailyCheckInSection()
            CloudAISettingsSection()
            privacySection
            helpSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .tint(.appAccent)
        .confirmationDialog(
            "Delete this profile?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete “\(profile.name)”") {
                delete(profile)
            }
            Button("Keep", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { _ in
            Text("Its tone, times of day and focus presets go with it. Your tasks and reminders stay.")
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                hasSeenWelcome = true
                showWelcome = false
            }
        }
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        Section {
            ForEach(profiles) { profile in
                NavigationLink {
                    ProfileDetailView(profile: profile)
                } label: {
                    profileRow(profile)
                }
                .listRowBackground(Color.appSurface)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        use(profile)
                    } label: {
                        Label("Use", systemImage: "checkmark.circle")
                    }
                    .tint(.appAccent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        Haptics.tap()
                        profilePendingDeletion = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.appSecondaryText)
                }
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text("A profile holds your tone, times of day and focus defaults. Swipe right on one to use it.")
        }
    }

    private func profileRow(_ profile: UserProfile) -> some View {
        let isActive = profile.id == activeProfileId

        return HStack(spacing: 8) {
            Text(profile.name.isEmpty ? "Unnamed" : profile.name)
                .foregroundStyle(.appPrimaryText)

            Spacer(minLength: 8)

            if isActive {
                Text("In use")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.appAccent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var addProfileSection: some View {
        Section("Add a profile") {
            HStack(spacing: 12) {
                TextField("Name", text: $newName)
                    .submitLabel(.done)
                    .onSubmit {
                        addProfile()
                    }

                Button("Add") {
                    addProfile()
                }
                .buttonStyle(.borderless)
                .disabled(trimmedNewName.isEmpty)
            }
            .listRowBackground(Color.appSurface)
        }
    }

    // MARK: - Focus & Refocus (app-wide)

    private var focusSection: some View {
        Section {
            Toggle("Keep screen awake during focus", isOn: $keepScreenAwake)
                .listRowBackground(Color.appSurface)
            Toggle("Breathing haptics", isOn: $hapticBreathing)
                .listRowBackground(Color.appSurface)
        } header: {
            Text("Focus & Refocus")
        } footer: {
            Text("Breathing haptics are soft taps that pace each breath in Refocus. Focus lengths, presets and your mantra live in each profile.")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Link(destination: Self.privacyURL) {
                linkLabel("Privacy Policy", systemImage: "hand.raised")
            }
            .listRowBackground(Color.appSurface)

            Link(destination: Self.supportURL) {
                linkLabel("Support", systemImage: "lifepreserver")
            }
            .listRowBackground(Color.appSurface)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Your thoughts, tasks and focus sessions stay on this iPhone. Reminders and check-ins are scheduled here too.")
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        Section("Help") {
            Link(destination: Self.howToURL) {
                linkLabel("How to use WithYou", systemImage: "questionmark.circle")
            }
            .listRowBackground(Color.appSurface)

            Button {
                Haptics.tap()
                hasSeenWelcome = false
                showWelcome = true
            } label: {
                Label("Show welcome again", systemImage: "sparkles")
            }
            .listRowBackground(Color.appSurface)
        }
    }

    private func linkLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { newValue in
                if !newValue { profilePendingDeletion = nil }
            }
        )
    }

    private func use(_ profile: UserProfile) {
        Haptics.tap()
        ProfileStore.appState(in: context).activeProfileId = profile.id
        do {
            try context.save()
        } catch {
            print("❌ Save failed (use profile):", error)
        }
    }

    private func addProfile() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }

        let profile = UserProfile(name: name)
        context.insert(profile)

        let state = ProfileStore.appState(in: context)
        if state.activeProfileId == nil {
            state.activeProfileId = profile.id
        }

        do {
            try context.save()
            Haptics.success()
            newName = ""
        } catch {
            Haptics.error()
            print("❌ Save failed (add profile):", error)
        }
    }

    private func delete(_ profile: UserProfile) {
        profilePendingDeletion = nil
        // Also removes its focus presets and repairs the active profile (creating "Me" if needed).
        ProfileStore.deleteProfile(profile, in: context)
        Haptics.success()
    }
}

// MARK: - Profile detail

private struct ProfileDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    @Query(sort: [
        SortDescriptor<FocusDurationPreset>(\.sortOrder, order: .forward),
        SortDescriptor<FocusDurationPreset>(\.createdAt, order: .forward)
    ]) private var allPresets: [FocusDurationPreset]

    private var presets: [FocusDurationPreset] {
        allPresets.filter { $0.profileId == profile.id }
    }

    private static let focusMinuteChoices: [Int] = Array(stride(from: 10, through: 90, by: 5))

    var body: some View {
        Form {
            basicsSection
            appearanceSection
            timesSection
            focusSection
            if !presets.isEmpty {
                presetsSection
            }
            refocusSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(profile.name.isEmpty ? "Profile" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.appAccent)
        .onDisappear {
            try? context.save()
        }
    }

    // MARK: Sections

    private var basicsSection: some View {
        Section {
            TextField("Name", text: $profile.name)
                .listRowBackground(Color.appSurface)

            Picker("Tone", selection: $profile.toneRaw) {
                Text("Gentle").tag(ReminderTone.gentle.rawValue)
                Text("Firm").tag(ReminderTone.firm.rawValue)
            }
            .listRowBackground(Color.appSurface)
        } header: {
            Text("Basics")
        } footer: {
            Text("Gentle: soft invitations. Firm: shorter and more direct. Never pushy.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: themeBinding) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Text(scheme.label).tag(scheme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.appSurface)
        }
    }

    private var timesSection: some View {
        Section {
            hourPicker("Morning", selection: $profile.morningHour, range: 5...12)
            hourPicker("Afternoon", selection: $profile.afternoonHour, range: 12...17)
            hourPicker("Evening", selection: $profile.eveningHour, range: 17...23)
        } header: {
            Text("Times of day")
        } footer: {
            Text("Used for suggestions like “Tomorrow morning” and “This evening.”")
        }
    }

    private var focusSection: some View {
        Section("Focus") {
            Picker("Default focus length", selection: $profile.defaultFocusMinutes) {
                ForEach(
                    pickerOptions(Self.focusMinuteChoices, including: profile.defaultFocusMinutes),
                    id: \.self
                ) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .listRowBackground(Color.appSurface)

            Toggle("Send captures to Brain Dump during focus", isOn: $profile.routeSiriToFocusDumpWhenActive)
                .listRowBackground(Color.appSurface)
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(presets) { preset in
                presetRow(preset)
                    .listRowBackground(Color.appSurface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Haptics.tap()
                            FocusPresetStore.delete(preset, in: context)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .tint(.appSecondaryText)
                    }
            }
        } header: {
            Text("Focus presets")
        } footer: {
            Text("Swipe left on a preset to remove it.")
        }
    }

    private var refocusSection: some View {
        Section("Refocus") {
            TextField("Mantra", text: $profile.defaultMantra)
                .listRowBackground(Color.appSurface)
        }
    }

    // MARK: Rows

    private func hourPicker(_ title: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(pickerOptions(Array(range), including: selection.wrappedValue), id: \.self) { hour in
                Text(hourLabel(hour)).tag(hour)
            }
        }
        .listRowBackground(Color.appSurface)
    }

    private func presetRow(_ preset: FocusDurationPreset) -> some View {
        let minutesText = "\(preset.minutes) min"
        let label = preset.label.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 8) {
            Text(label.isEmpty ? minutesText : label)
                .foregroundStyle(.appPrimaryText)

            if !label.isEmpty && label != minutesText {
                Spacer(minLength: 8)
                Text(minutesText)
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Bindings

    /// Saving is enough: RootView reads the active profile's theme through @Query.
    private var themeBinding: Binding<String> {
        Binding(
            get: { profile.colorSchemeRaw },
            set: { newValue in
                Haptics.tap()
                profile.colorSchemeRaw = newValue
                try? context.save()
            }
        )
    }
}

/// `base`, plus `current` when it is not already a choice, so a Picker never shows a blank value
/// for a setting saved before the choices changed.
private func pickerOptions(_ base: [Int], including current: Int) -> [Int] {
    base.contains(current) ? base : (base + [current]).sorted()
}
