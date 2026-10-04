//
//  SharedAppGroup.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// App Group shared between the app and the widget extension (Epic 5, F5.6), so both can see
/// the same Enphase monthly request budget without independently exceeding it. The widget
/// extension has its own minimal, duplicated copy of this constant (see
/// `EnergieWidget/PVWidgetDataSource.swift`) — there is no supported way with the available
/// project-editing tools to share a single source file's compilation across both targets
/// without introducing a separate framework target, so this one small constant is intentionally
/// kept in sync by hand rather than shared.
enum SharedAppGroup {
    static let identifier = "group.de.florian.tobias.Energie"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// The private CloudKit container `EnergieApp` syncs `PVDailySample`/`PVYearlySample`/
    /// `HeatPumpEfficiencySample` through (Epic 0, F0.1) — see BACKLOG.md, "Nicht umsetzbar ohne
    /// kostenpflichtigen Apple Developer Account" for why this was blocked until now.
    static let cloudKitContainerIdentifier = "iCloud.de.florian.tobias.Energie"
}
