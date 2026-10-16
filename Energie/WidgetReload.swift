//
//  WidgetReload.swift
//  Energie
//
//  Created by Tobias Florian on 16.10.26.
//

import WidgetKit

/// Nudges WidgetKit to refresh the Shelly-related Homescreen widgets sooner than their own
/// 15-minute poll cadence (`ShellyWidgetProvider.pollInterval`, F16.3) would on its own — after a
/// successful schalten (F13.1) and when the app leaves the foreground, so the widget doesn't keep
/// showing a state the user just changed from inside the app. Deliberately *not* tied to
/// `ShellyModel`'s regular 60s poll loop — that would just have the widget re-fetch on every tick
/// regardless of whether anything changed.
///
/// The kind strings have to match `ShellyWidget`/`CombinedWidget`'s own `kind` property exactly —
/// duplicated by hand rather than shared, same reasoning as `SharedAppGroup`'s doc comment:
/// there's no supported way with the available project-editing tools to share a single source
/// file's compilation across both targets without introducing a separate framework target.
enum WidgetReload {
    static func shellyWidgetsChanged() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ShellyWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CombinedWidget")
    }
}
