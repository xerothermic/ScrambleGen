import AppIntents
import SwiftUI
import WidgetKit

// Watch-face complication: shows the chosen puzzle and, when tapped, opens
// the app on that puzzle (scramblegen://puzzle/<slug>, handled by
// ContentView.onOpenURL). Puzzle, its colours and the URL format are shared
// with the app via ScrambleGenerator.swift and PuzzleStyle.swift.

// MARK: - Intent

extension Puzzle: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Puzzle" }
    static var caseDisplayRepresentations: [Puzzle: DisplayRepresentation] {
        [.cube3x3: DisplayRepresentation(title: "3×3"),
         .square1: DisplayRepresentation(title: "Square-1")]
    }
}

struct SelectPuzzleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Scramble" }
    static var description: IntentDescription {
        IntentDescription("Choose which puzzle the complication opens.")
    }

    @Parameter(title: "Puzzle", default: .cube3x3)
    var puzzle: Puzzle

    init() {}
    init(puzzle: Puzzle) { self.puzzle = puzzle }
}

// MARK: - Timeline

struct PuzzleEntry: TimelineEntry {
    let date: Date
    let puzzle: Puzzle
}

struct PuzzleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PuzzleEntry {
        PuzzleEntry(date: .now, puzzle: .cube3x3)
    }

    func snapshot(for configuration: SelectPuzzleIntent, in context: Context) async -> PuzzleEntry {
        PuzzleEntry(date: .now, puzzle: configuration.puzzle)
    }

    func timeline(for configuration: SelectPuzzleIntent, in context: Context) async -> Timeline<PuzzleEntry> {
        // Static content: one entry, never needs a refresh.
        Timeline(entries: [PuzzleEntry(date: .now, puzzle: configuration.puzzle)], policy: .never)
    }

    // watchOS lists these in the face editor's complication gallery.
    func recommendations() -> [AppIntentRecommendation<SelectPuzzleIntent>] {
        Puzzle.allCases.map {
            AppIntentRecommendation(intent: SelectPuzzleIntent(puzzle: $0),
                                    description: Text($0.name))
        }
    }
}

// MARK: - View

struct ScrambleComplicationView: View {
    let entry: PuzzleEntry
    @Environment(\.widgetFamily) private var family

    private var puzzle: Puzzle { entry.puzzle }

    var body: some View {
        content
            .widgetURL(puzzle.deepLink)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: puzzle.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(puzzle.cardColor)
                        .widgetAccentable()
                    Text(puzzle.shortName)
                        .font(.system(size: 12, weight: .bold))
                        .minimumScaleFactor(0.7)
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: puzzle.symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(puzzle.cardColor)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Watch Scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(puzzle.name)
                        .font(.headline)
                    Text("Tap to scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryCorner:
            Image(systemName: puzzle.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(puzzle.cardColor)
                .widgetAccentable()
                .widgetLabel { Text(puzzle.name) }
        case .accessoryInline:
            Label(puzzle.name, systemImage: puzzle.symbolName)
        default:
            Text(puzzle.shortName)
        }
    }
}

// MARK: - Widget

@main
struct ScrambleComplication: Widget {
    static let kind = "ScrambleComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: SelectPuzzleIntent.self,
                               provider: PuzzleProvider()) { entry in
            ScrambleComplicationView(entry: entry)
        }
        .configurationDisplayName("Scramble")
        .description("Open Watch Scramble on a puzzle of your choice.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular,
                            .accessoryCorner, .accessoryInline])
    }
}
