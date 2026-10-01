//
//  AccentColors.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import SwiftUI

/// Section accent colors. Kept distinct per energy source so PV and heat-pump screens stay
/// visually separable even as they share the same UI building blocks (see
/// Plans/Waermepumpe-Integration.md, Abschnitt 3).
extension ShapeStyle where Self == Color {
    static var pvAccent: Color { .orange }
    static var heatPumpAccent: Color { .indigo }
}
