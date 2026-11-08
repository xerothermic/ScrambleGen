import Foundation

/// Settings + dispatch for the Scramble/Timer cards (app only; the complication
/// keeps using the plain random-move generator).
enum ScrambleSource {
    static let randomStateKey = "scramble.randomState3x3"
    static let defaultRandomState = true

    static var randomStateEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: randomStateKey) == nil ? defaultRandomState : d.bool(forKey: randomStateKey)
    }

    /// Build the solver tables off the main thread; no-op when already built.
    static func prewarm() {
        guard !RandomState333.isReady else { return }
        Task.detached(priority: .utility) { _ = RandomState333.prepare() }
    }

    /// New scramble for `puzzle`. 3x3 uses a random-state scramble when
    /// enabled and the tables are built; otherwise (first seconds after
    /// launch, or toggle off) the random-move generator answers immediately.
    static func next(for puzzle: Puzzle, length: Int) async -> [String] {
        if puzzle == .cube3x3 && randomStateEnabled {
            if RandomState333.isReady {
                return await Task.detached(priority: .userInitiated) {
                    RandomState333.randomScramble()
                }.value
            }
            prewarm()
        }
        return puzzle.generate(length: length)
    }
}
