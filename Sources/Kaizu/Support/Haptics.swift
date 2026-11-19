import AppKit

/// The trackpad's light tap, felt on a Force Touch trackpad while a finger
/// is on it (and only then): a drag landing somewhere it can drop or rest.
enum Haptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
