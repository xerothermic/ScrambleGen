import SwiftUI

// Shared by the Watch App and the ScrambleWidgetExtension (complication), so
// both draw a puzzle the same way and agree on the deep-link format.

extension Puzzle {
    /// Card / panel colour for this puzzle.
    var cardColor: Color {
        switch self {
        case .cube3x3: Color(red: 0.19, green: 0.82, blue: 0.35)  // cube green
        case .square1: Color(red: 0.81, green: 0.13, blue: 0.16)  // WCA front red
        }
    }

    /// SF Symbol used by the watch-face complication.
    var symbolName: String {
        switch self {
        case .cube3x3: "cube.fill"
        case .square1: "square.split.diagonal"
        }
    }

    /// Very short label that fits a circular complication.
    var shortName: String {
        switch self {
        case .cube3x3: "3×3"
        case .square1: "Sq-1"
        }
    }

    /// Path component in the deep link: scramblegen://puzzle/3x3
    var urlSlug: String {
        switch self {
        case .cube3x3: "3x3"
        case .square1: "square1"
        }
    }

    /// The URL a complication opens to land on this puzzle.
    var deepLink: URL {
        URL(string: "scramblegen://puzzle/\(urlSlug)")!
    }

    /// Parses scramblegen://puzzle/<slug>; nil for anything else.
    init?(deepLink url: URL) {
        guard url.scheme == "scramblegen", url.host == "puzzle",
              let match = Puzzle.allCases.first(where: { $0.urlSlug == url.lastPathComponent })
        else { return nil }
        self = match
    }
}

/// What a complication can open: one of the puzzles, or the Timer card (which
/// is not a `Puzzle`). Raw values match `Puzzle`'s so complications configured
/// before the Timer option existed keep their choice.
enum ComplicationTarget: String, CaseIterable {
    case cube3x3
    case square1
    case timer

    init(_ puzzle: Puzzle) {
        switch puzzle {
        case .cube3x3: self = .cube3x3
        case .square1: self = .square1
        }
    }

    /// The puzzle this opens; nil for the Timer card.
    var puzzle: Puzzle? { Puzzle(rawValue: rawValue) }

    var name: String {
        switch self {
        case .timer: "Timer"
        default: puzzle?.name ?? "Timer"
        }
    }

    var shortName: String {
        switch self {
        case .timer: "Timer"
        default: puzzle?.shortName ?? "Timer"
        }
    }

    var symbolName: String {
        switch self {
        case .timer: "stopwatch.fill"
        default: puzzle?.symbolName ?? "stopwatch.fill"
        }
    }

    /// The URL a complication opens: scramblegen://puzzle/<slug> or
    /// scramblegen://timer.
    var deepLink: URL {
        switch self {
        case .timer: URL(string: "scramblegen://timer")!
        default: puzzle?.deepLink ?? URL(string: "scramblegen://timer")!
        }
    }

    /// Parses either deep-link form; nil for anything else.
    init?(deepLink url: URL) {
        if url.scheme == "scramblegen", url.host == "timer" {
            self = .timer
        } else if let puzzle = Puzzle(deepLink: url) {
            self = ComplicationTarget(puzzle)
        } else {
            return nil
        }
    }
}
