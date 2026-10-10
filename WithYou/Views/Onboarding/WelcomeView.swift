//
//  WelcomeView.swift
//  WithYou
//

import SwiftUI

/// A short, calm introduction shown once on first launch.
/// Three pages, a "Get started" button, and "Skip" for anyone who wants to go straight in.
struct WelcomeView: View {
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pages = WelcomePage.all

    private var isLastPage: Bool { page >= pages.count - 1 }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                skipBar

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        WelcomePageView(page: item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: pages.count, current: page)
                    .padding(.vertical, 12)

                Button {
                    advance()
                } label: {
                    Text(isLastPage ? "Get started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.appAccent)
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Skip") {
                Haptics.tap()
                onDone()
            }
            .foregroundStyle(.appSecondaryText)
            .opacity(isLastPage ? 0 : 1)
            .disabled(isLastPage)
            .accessibilityHidden(isLastPage)
            .accessibilityHint("Closes the introduction")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func advance() {
        Haptics.tap()
        guard !isLastPage else {
            onDone()
            return
        }
        if reduceMotion {
            page += 1
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                page += 1
            }
        }
    }
}

// MARK: - Pages

private struct WelcomePage: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let message: String
    var note: String? = nil

    static let all: [WelcomePage] = [
        WelcomePage(
            id: 0,
            symbol: "tray.and.arrow.down",
            title: "Get it out of your head",
            message: "Capture a thought the moment it shows up. It waits in your Inbox, parked, not promised. Thoughts aren’t obligations."
        ),
        WelcomePage(
            id: 1,
            symbol: "sun.max",
            title: "One thing at a time",
            message: "Today shows just what matters right now. Nothing is ever overdue. If a time passes, you can pick a new one or let it go."
        ),
        WelcomePage(
            id: 2,
            symbol: "timer",
            title: "Protect a little focus",
            message: "Start a focus session for as long as feels right. Short ones count. If things get noisy, Refocus takes about a minute, and “I’m stuck” finds a smaller first step.",
            note: "Notifications are optional. WithYou only asks when you schedule something."
        )
    ]
}

private struct WelcomePageView: View {
    let page: WelcomePage

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var circleSize: CGFloat = 96

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: page.symbol)
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(.appAccent)
                        .frame(width: circleSize, height: circleSize)
                        .background(
                            Circle().fill(Color.appAccent.opacity(0.12))
                        )
                        .accessibilityHidden(true)

                    Text(page.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.appPrimaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(page.message)
                        .font(.body)
                        .foregroundStyle(.appSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = page.note {
                        Label(note, systemImage: "bell")
                            .font(.footnote)
                            .foregroundStyle(.appSecondaryText)
                            .cardStyle(padding: 12, cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 520)
                // Centered when it fits; scrolls at large text sizes.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.appAccent : Color.appSecondaryText.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

#Preview {
    WelcomeView(onDone: {})
}
