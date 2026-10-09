//
//  Feedback.swift
//  DankHome
//

import AudioToolbox
import UIKit

/// Haptics plus an optional soft click (Settings › Dashboard › Click Sounds).
enum Feedback {
    /// Light taps: toggles, chips.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        click()
    }

    /// Firmer: scenes, long presses, confirmations.
    static func press() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        click()
    }

    /// Detents while sliding (every 10% brightness).
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private static func click() {
        guard AppStores.shared.settings.prefs.clickSounds else { return }
        AudioServicesPlaySystemSound(1104)  // the system keyboard click
    }
}
