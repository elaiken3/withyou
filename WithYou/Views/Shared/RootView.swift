//
//  RootView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData
import OSLog

private let routingLog = Logger(subsystem: "com.commongenelabs.WithYou", category: "routing")

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var selectedTab: AppTab = .today
    @State private var showRefocus = false
    @State private var showVoiceCapture = false
    /// What the last voice capture saved; shown as a toast once its sheet has closed.
    @State private var voiceSaveSummary: CaptureSaveSummary?
    @State private var toast: Toast?
    @State private var showWelcome = false
    @State private var didRunLaunchSetup = false

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    // The appearance setting lives on the active profile. Reading it through @Query keeps
    // the whole app in sync the moment the profile changes.
    @Query private var appStates: [AppState]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var router: AppRouter { AppRouter.shared }

    private var activeProfile: UserProfile? {
        if let id = appStates.first?.activeProfileId,
           let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.ordered, id: \.self) { tab in
                tabView(for: tab)
                    .tag(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            }
        }
        .tint(.appAccent)
        .preferredColorScheme(activeProfile?.colorScheme.preferred)
        .sheet(isPresented: $showRefocus) {
            RefocusView()
        }
        .sheet(isPresented: $showVoiceCapture, onDismiss: showVoiceSaveToast) {
            VoiceCaptureView { summary in
                voiceSaveSummary = summary
            }
        }
        // Sits above the tab bar. Only the toast itself takes touches.
        .overlay(alignment: .bottom) {
            Color.clear
                .allowsHitTesting(false)
                .toast($toast)
                .padding(.bottom, 60)
        }
        .fullScreenCover(isPresented: $showWelcome, onDismiss: {
            // Anything that arrived while the welcome was up (e.g. a Siri shortcut).
            handle(router.pendingRoute)
        }) {
            WelcomeView {
                finishWelcome()
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            runLaunchSetupIfNeeded()
            // A cold launch from a notification or Siri sets the route before any view exists.
            handle(router.pendingRoute)
        }
        .onChange(of: router.pendingRoute) { _, route in
            handle(route)
        }
        // `withyou://voice` and friends (the `withyou` scheme is registered in Info.plist).
        .onOpenURL { url in
            router.open(deepLink: url.absoluteString)
        }
    }

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(selectedTab: $selectedTab)
        case .focus:
            FocusSessionFlowView(selectedTab: $selectedTab)
        case .inbox:
            InboxView()
        case .schedule:
            ScheduleView()
        case .capture:
            QuickAddView()
        }
    }

    // MARK: - Launch

    private func runLaunchSetupIfNeeded() {
        guard !didRunLaunchSetup else { return }
        didRunLaunchSetup = true

        ProfileStore.ensureDefaultProfile(in: context)
        FocusSessionStore.normalizeActiveSessions(in: context)

        guard !hasSeenWelcome else { return }
        // Appear in place rather than sliding up over the tabs on first launch.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showWelcome = true
        }
    }

    private func finishWelcome() {
        hasSeenWelcome = true
        showWelcome = false
    }

    // MARK: - Routing

    /// Implements the `AppRouter` contract (see AppRouter.swift).
    private func handle(_ route: AppRoute?) {
        guard let route else { return }
        // Nothing can be presented over the welcome; the route waits until it closes.
        guard !showWelcome else { return }

        switch route {
        case .today:
            selectedTab = .today
            router.consume()
        case .focus:
            selectedTab = .focus
            router.consume()
        case .inbox:
            selectedTab = .inbox
            router.consume()
        case .schedule:
            selectedTab = .schedule
            router.consume()
        case .capture:
            selectedTab = .capture
            router.consume()
        case .refocus:
            router.consume()
            showRefocus = true
        case .startFocus(let reminderId):
            router.consume()
            startFocus(forReminder: reminderId)
        case .voiceCapture:
            router.consume()
            presentVoiceCapture()
        case .stuck, .reminder:
            // TodayView presents the sheet and consumes the route.
            selectedTab = .today
        }
    }

    // MARK: - Voice capture

    private func presentVoiceCapture() {
        guard !showVoiceCapture else { return }
        // One sheet at a time: let Refocus close first.
        guard showRefocus else {
            showVoiceCapture = true
            return
        }
        showRefocus = false
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showVoiceCapture = true
        }
    }

    private func showVoiceSaveToast() {
        guard let summary = voiceSaveSummary else { return }
        voiceSaveSummary = nil
        toast = Toast(
            text: CaptureSaver.message(for: summary),
            actionTitle: "Undo",
            action: {
                CaptureSaver.undo(summary, in: context)
            }
        )
    }

    // MARK: - Focus

    private func startFocus(forReminder reminderId: UUID) {
        let descriptor = FetchDescriptor<VerboseReminder>(
            predicate: #Predicate<VerboseReminder> { $0.id == reminderId }
        )
        guard let reminder = (try? context.fetch(descriptor))?.first else {
            // Let go or finished in the meantime. Just open Today calmly.
            selectedTab = .today
            return
        }

        // Already focusing on this reminder (for example, "I'm starting" tapped twice).
        if let active = FocusSessionStore.activeSession(in: context),
           active.sourceId == reminderId,
           active.startedAt != nil {
            selectedTab = .focus
            return
        }

        let profileMinutes = ProfileStore.activeProfile(in: context)?.defaultFocusMinutes ?? 25
        let minutes = profileMinutes > 0 ? profileMinutes : 25

        reminder.isStarted = true
        do {
            try FocusSessionStore.start(
                title: reminder.title,
                startStep: reminder.startStep,
                durationSeconds: minutes * 60,
                sourceKind: .reminder,
                sourceId: reminder.id,
                beginImmediately: true,
                in: context
            )
        } catch {
            routingLog.error("Could not start focus from a reminder: \(String(describing: error), privacy: .public)")
        }
        selectedTab = .focus
    }
}
