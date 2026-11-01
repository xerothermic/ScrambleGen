import Foundation

/// Single place that decides whether the premium features are available.
///
/// Premium covers: persistent solve history beyond the last 20, the stats and
/// charts screens, and the experimental "Motion insights" (quiet time).
///
/// For now everything is unlocked (`isUnlocked == true`, no purchase exists).
/// When StoreKit is added, turn `isUnlocked` into a computed property backed by
/// the verified entitlement (non-consumable) and keep every premium screen
/// asking this one flag, so the gate stays in one spot. Free data collection
/// (recording solves) deliberately does not check it: a locked user keeps
/// their history, they just can't open the premium screens.
struct PremiumFeatures {
    /// TODO(StoreKit): replace with the entitlement check.
    static let isUnlocked = true
}

/// Setting keys and limits for "Motion insights" (opt-in motion recording and
/// the experimental quiet-time analysis).
enum MotionInsights {
    /// @AppStorage key. Default off.
    static let key = "motionInsights"
    /// The one-line honest explanation shown next to the toggle.
    static let explanation = "Records wrist motion while you solve. Stays on this watch."
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}
