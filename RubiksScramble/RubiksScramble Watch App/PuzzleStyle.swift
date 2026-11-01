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
