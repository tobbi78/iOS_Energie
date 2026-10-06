//
//  LaunchView.swift
//  Energie
//
//  Created by Tobias Florian on 06.10.26.
//

import SwiftUI

/// Animated launch screen shown as an overlay over `ContentView`'s `TabView` while the first PV/
/// heat-pump data is still loading (F10.1, BACKLOG.md Epic 10). Reuses the app's existing
/// two-source branding — `.pvAccent`/`.heatPumpAccent` (see `AccentColors.swift`) and the same
/// `sun.max.fill`/`heater.vertical.fill` icons as the tab bar — so no new icon asset is needed.
///
/// Deliberately shows no text that duplicates the real section names ("PV-Anlage"/"Wärmepumpe"):
/// `EnergieUITests` looks up those exact strings to navigate, and an overlay carrying the same
/// text would make those lookups ambiguous while the launch screen is still on screen.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var iconsVisible = false
    @State private var isPulsing = false
    @State private var titleVisible = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                HStack(spacing: 36) {
                    glowingIcon(systemName: "sun.max.fill", tint: .pvAccent)
                    glowingIcon(systemName: "heater.vertical.fill", tint: .heatPumpAccent, pulseDelay: 0.3)
                }
                .accessibilityHidden(true)

                Text("Energie")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("launchScreen")
        .onAppear(perform: animateIn)
    }

    @ViewBuilder
    private func glowingIcon(systemName: String, tint: Color, pulseDelay: Double = 0) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.35))
                .frame(width: 72, height: 72)
                .blur(radius: 16)
                .scaleEffect(isPulsing ? 1.15 : 0.9)
            Image(systemName: systemName)
                .font(.system(size: 40))
                .foregroundStyle(tint)
        }
        .scaleEffect(iconsVisible ? 1 : 0.8)
        .opacity(iconsVisible ? 1 : 0)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(pulseDelay),
            value: isPulsing
        )
    }

    private func animateIn() {
        if reduceMotion {
            iconsVisible = true
            titleVisible = true
            return
        }
        withAnimation(.spring(duration: 0.18)) {
            iconsVisible = true
        }
        withAnimation(.easeOut(duration: 0.15).delay(0.03)) {
            titleVisible = true
        }
        isPulsing = true
    }
}

#Preview("Light") {
    LaunchView()
}

#Preview("Dark") {
    LaunchView()
        .preferredColorScheme(.dark)
}
