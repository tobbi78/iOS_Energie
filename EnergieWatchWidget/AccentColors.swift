//
//  AccentColors.swift
//  EnergieWatchWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Mirrors the iPhone app's `UI/AccentColors.swift` and the Watch app's own copy, so PV and
//  heat-pump complications use the same accent colors. Duplicated rather than shared — same
//  tooling constraint as the rest of the Watch code.

import SwiftUI

extension ShapeStyle where Self == Color {
    static var pvAccent: Color { .orange }
    static var heatPumpAccent: Color { .indigo }
}
