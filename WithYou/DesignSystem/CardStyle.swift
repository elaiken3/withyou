//
//  CardStyle.swift
//  WithYou
//

import SwiftUI

// MARK: - Card

/// The standard WithYou card: surface fill, hairline border, soft shadow.
/// Use `.cardStyle()` instead of repeating the background/overlay/shadow stack.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.appHairline.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 14, cornerRadius: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Section header

/// Calm section heading used on Today and similar screens.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.appPrimaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Toast

/// A short, calm confirmation ("Saved.", "Moved to 7:00 PM.") with an optional action such as Undo.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let toast: Toast
    var dismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.footnote)
                .foregroundStyle(.appPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    Haptics.tap()
                    action()
                    dismiss()
                }
                .font(.footnote.weight(.semibold))
                .tint(.appAccent)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast) { self.toast = nil }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: toast)
            // Restarts whenever a new toast replaces the old one, so an earlier
            // timer can never hide a newer message early.
            .task(id: toast?.id) {
                guard let current = toast else { return }
                AccessibilityNotification.Announcement(current.text).post()
                let seconds: Double = current.action == nil ? 2.5 : 4.5
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, toast?.id == current.id else { return }
                toast = nil
            }
    }
}

extension View {
    /// Shows `toast` at the bottom of the view and clears it after a moment.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastPresenter(toast: toast))
    }
}
