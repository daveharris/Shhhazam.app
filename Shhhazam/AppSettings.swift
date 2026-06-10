//
//  AppSettings.swift
//  Shhhazam
//
//  User-configurable settings, persisted to UserDefaults.
//

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    /// Trigger level in dBFS. Mic input is ~ -80 (silence) ... 0 (full scale).
    @Published var thresholdDBFS: Double {
        didSet { defaults.set(thresholdDBFS, forKey: Keys.threshold) }
    }

    /// How long the level must stay above the threshold before alerting,
    /// so a sneeze or cough doesn't trigger it.
    @Published var sustainSeconds: Double {
        didSet { defaults.set(sustainSeconds, forKey: Keys.sustain) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let threshold = "thresholdDBFS"
        static let sustain = "sustainSeconds"
    }

    init() {
        defaults.register(defaults: [
            Keys.threshold: -25.0,
            Keys.sustain: 2.0,
        ])
        thresholdDBFS = defaults.double(forKey: Keys.threshold)
        sustainSeconds = defaults.double(forKey: Keys.sustain)
    }
}
