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
    /// How the next voice capture opens: empty and listening from a route, or with the words
    /// Undo gave back and the mic off.
    @State private var voiceStart = VoiceStart()
    /// What the last voice capture saved, and its words; shown as a toast once its sheet has closed.
    @State private var voiceSave: VoiceSave?
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
            VoiceCaptureView(
                initialText: voiceStart.text,
                autoStart: voiceStart.autoStart,
                onSaved: { summary, words in
                    voiceSave = VoiceSave(summary: summary, words: words)
                },
                onClose: { words in
                    offerClosedWords(words)
                }
            )
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
        // Another screen needs its sheet up (see `AppRouter.closeAllSheets()`).
        .onChange(of: router.closeSheetsRequest) { _, _ in
            showRefocus = false
            showVoiceCapture = false
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
            presentRefocus()
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

    // MARK: - Sheets

    private enum RootSheet {
        case refocus
        case voiceCapture
    }

    /// Only one sheet can be up at a time, and the tabs present their own. When anything is
    /// up (here or in a tab), everything is asked to close first, then the sheet is shown.
    private func present(_ sheet: RootSheet) {
        guard showRefocus || showVoiceCapture || router.isSheetUp else {
            show(sheet)
            return
        }
        // Also closes Refocus and voice capture here (see `onChange(of: closeSheetsRequest)`).
        router.closeAllSheets()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            show(sheet)
        }
    }

    private func show(_ sheet: RootSheet) {
        switch sheet {
        case .refocus:
            showRefocus = true
        case .voiceCapture:
            showVoiceCapture = true
        }
    }

    private func presentRefocus() {
        guard !showRefocus else { return }
        // Someone is talking: don't close their words away for Refocus.
        guard !router.isVoiceCaptureOpen else { return }
        present(.refocus)
    }

    // MARK: - Voice capture

    private struct VoiceStart {
        var text = ""
        var autoStart = true
    }

    private struct VoiceSave {
        let summary: CaptureSaveSummary
        let words: String
    }

    /// From a route (empty, listening right away), or from Undo (the words back, mic off).
    private func presentVoiceCapture(initialText: String = "", autoStart: Bool = true) {
        // Already open, here or in Capture: leave it, and the words in it, alone.
        guard !router.isVoiceCaptureOpen else { return }
        voiceStart = VoiceStart(text: initialText, autoStart: autoStart)
        present(.voiceCapture)
    }

    private func showVoiceSaveToast() {
        guard let save = voiceSave else { return }
        voiceSave = nil
        toast = Toast(
            text: CaptureSaver.message(for: save.summary),
            actionTitle: "Undo",
            action: {
                CaptureSaver.undo(save.summary, in: context)
                // Nothing is lost: the words come back to look over (or say more).
                if !save.words.isEmpty {
                    presentVoiceCapture(initialText: save.words, autoStart: false)
                }
            }
        )
    }

    /// Voice capture closed without saving. Its words can come back with Undo.
    private func offerClosedWords(_ words: String) {
        guard !words.isEmpty else { return }
        toast = Toast(
            text: "Closed without saving.",
            actionTitle: "Undo",
            action: {
                presentVoiceCapture(initialText: words, autoStart: false)
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
