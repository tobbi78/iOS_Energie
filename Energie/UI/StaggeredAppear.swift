//
//  StaggeredAppear.swift
//  Energie
//
//  Created by Tobias Florian on 10.10.26.
//

import SwiftUI

extension EnvironmentValues {
    /// Whether `ContentView`'s `LaunchView` overlay (F10.1) is still covering the UI. Views that
    /// animate in on appear wait for this to turn `false`, otherwise their animation would play
    /// unseen behind the overlay (e.g. on a cache hit).
    @Entry var isLaunchScreenVisible = false
}

/// Staggered fade/scale-in for KPI tiles (F10.3, BACKLOG.md Epic 10): each card appears slightly
/// after the previous one, delayed proportionally to its grid `index`.
///
/// Driven by `onAppear` plus local `@State` instead of a `.transition`, because a transition only
/// plays if the insertion happens inside `withAnimation` — the model state changes that insert
/// the cards are not animated. Since the state is tied to the view's identity, the animation
/// plays only when a card is actually inserted (e.g. `.loading` → `.ready`), not on refreshes
/// or when returning to a tab.
private struct StaggeredAppearModifier: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLaunchScreenVisible) private var isLaunchScreenVisible
    @State private var isVisible = false

    private static let delayPerIndex = 0.06

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.92)
            .offset(y: isVisible || reduceMotion ? 0 : 8)
            .onAppear {
                if !isLaunchScreenVisible { animateIn() }
            }
            .onChange(of: isLaunchScreenVisible) { _, isVisibleNow in
                if !isVisibleNow { animateIn() }
            }
    }

    private func animateIn() {
        guard !isVisible else { return }
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(duration: 0.35, bounce: 0.2).delay(Double(index) * Self.delayPerIndex)
        withAnimation(animation) {
            isVisible = true
        }
    }
}

extension View {
    /// Fades/scales the view in on first appearance, delayed by its position `index` in a grid
    /// (F10.3).
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppearModifier(index: index))
    }
}
