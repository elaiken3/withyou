//
//  CloudAISettings.swift
//  WithYou
//

import Foundation
import SwiftUI

/// The person's choice about cloud AI. Off by default.
enum CloudAISettings {
    /// UserDefaults key; also used by `@AppStorage` in `CloudAISettingsSection`.
    static let enabledKey = "cloudAIEnabled"

    /// Whether the person turned cloud AI on.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Whether this build knows where cloud AI lives (a Supabase project is configured).
    static var isConfigured: Bool {
        AppConfig.supabaseBaseURL != nil && AppConfig.supabaseAnonKey != nil
    }
}

/// Settings rows for AI: what runs on this iPhone, the "Use cloud AI" choice, and a way to
/// delete what the server keeps. A `Section`, for use inside a `Form` or `List`.
///
/// Pass a toast binding to show results as a toast; otherwise they appear under the button.
struct CloudAISettingsSection: View {
    @AppStorage("cloudAIEnabled") private var cloudAIEnabled: Bool = false

    @State private var isDeleting = false
    @State private var message: String? = nil

    private let toast: Binding<Toast?>?

    init(toast: Binding<Toast?>? = nil) {
        self.toast = toast
    }

    var body: some View {
        Section {
            if AIService.isOnDeviceAvailable {
                Label(onDeviceStatusText, systemImage: "iphone")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .listRowBackground(Color.appSurface)
            }

            if CloudAISettings.isConfigured {
                Toggle("Use cloud AI", isOn: $cloudAIEnabled)
                    .listRowBackground(Color.appSurface)

                Button {
                    deleteCloudData()
                } label: {
                    HStack(spacing: 8) {
                        Text(isDeleting ? "Deleting…" : "Delete my cloud AI data")
                        Spacer(minLength: 8)
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
                .accessibilityHint("Removes the anonymous account and usage counts kept on WithYou’s server.")
                .listRowBackground(Color.appSurface)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.appSecondaryText)
                        .listRowBackground(Color.appSurface)
                }
            } else {
                Text("Cloud AI isn’t set up in this version of WithYou, so nothing is sent anywhere.")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .listRowBackground(Color.appSurface)
            }
        } header: {
            Text("AI help")
        } footer: {
            Text(footerText)
        }
    }

    /// Cloud AI also answers when Apple Intelligence can't (too slow, or no usable answer),
    /// so "stays on this iPhone" is only promised while cloud AI is off.
    private var onDeviceStatusText: String {
        if cloudAIEnabled && CloudAISettings.isConfigured {
            return "Apple Intelligence is on. Cloud AI is used only when it can’t help."
        }
        return "Apple Intelligence is on — requests stay on this iPhone."
    }

    private var footerText: String {
        if CloudAISettings.isConfigured {
            return "When Apple Intelligence isn’t available or can’t help, WithYou can send the text of each AI request to Claude (by Anthropic) through WithYou’s server, with a random ID instead of your name. WithYou’s server doesn’t keep your words. Off by default."
        }
        return "WithYou uses Apple Intelligence when this iPhone has it, and simple built-in suggestions otherwise."
    }

    private func deleteCloudData() {
        Haptics.tap()
        isDeleting = true
        message = nil
        let wasOn = cloudAIEnabled

        Task {
            var text: String
            do {
                let deleted = try await CloudAIClient.shared.deleteCloudData()
                cloudAIEnabled = false
                text = deleted ? "Your cloud AI data is deleted." : "Nothing is stored for you."
                if wasOn {
                    text += " Cloud AI is off now."
                }
            } catch {
                text = "Couldn’t reach WithYou’s server. Nothing changed, so you can try again later."
            }
            isDeleting = false
            show(text)
        }
    }

    private func show(_ text: String) {
        if let toast {
            toast.wrappedValue = Toast(text: text)
        } else {
            message = text
        }
    }
}
