//
//  AccentColors.swift
//  EnergieWatch Watch App
//
//  Created by Tobias Florian on 04.10.26.
//
//  Mirrors the iPhone app's `UI/AccentColors.swift` so PV and heat-pump cards use the same
//  accent colors on the Watch. Duplicated rather than shared — same tooling constraint as the
//  rest of the Watch code (see `WatchSnapshot.swift`).

import SwiftUI

extension ShapeStyle where Self == Color {
    static var pvAccent: Color { .orange }
    static var heatPumpAccent: Color { .indigo }
}
