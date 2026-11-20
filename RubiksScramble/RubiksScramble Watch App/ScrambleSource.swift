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

    static let square1RandomStateKey = "scramble.randomStateSquare1"
    static let defaultSquare1RandomState = true

    static var square1RandomStateEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: square1RandomStateKey) == nil
            ? defaultSquare1RandomState : d.bool(forKey: square1RandomStateKey)
    }

    /// Build the Square-1 solver tables off the main thread; no-op when
    /// already built. Called the first time Square-1 is needed.
    static func prewarmSquare1() {
        guard !Square1RandomState.isReady else { return }
        Task.detached(priority: .utility) { _ = Square1RandomState.prepare() }
    }

    /// Build the solver tables off the main thread; no-op when already built.
    static func prewarm() {
        guard !RandomState333.isReady else { return }
        Task.detached(priority: .utility) { _ = RandomState333.prepare() }
    }

    /// New scramble for `puzzle`. 3x3 and Square-1 use a random-state scramble
    /// when enabled and the tables are built; otherwise (while the tables are
    /// building, or toggle off) the random-move generator answers immediately.
    /// A random-state scramble has its own length (~20 moves / ~12-14 slices),
    /// so it is used only while the Length pill is at its default; moving the
    /// pill off the default gives a random-move scramble of exactly that length.
    static func next(for puzzle: Puzzle, length: Int) async -> [String] {
        guard length == puzzle.defaultLength else { return puzzle.generate(length: length) }
        if puzzle == .cube3x3 && randomStateEnabled {
            if RandomState333.isReady {
                return await Task.detached(priority: .userInitiated) {
                    RandomState333.randomScramble()
                }.value
            }
            prewarm()
        }
        if puzzle == .square1 && square1RandomStateEnabled {
            if Square1RandomState.isReady {
                let tokens: [String]? = await Task.detached(priority: .userInitiated) { () -> [String]? in
                    return Square1RandomState.randomScramble()
                }.value
                if let tokens { return tokens }
            } else {
                prewarmSquare1()
            }
        }
        return puzzle.generate(length: length)
    }
}
