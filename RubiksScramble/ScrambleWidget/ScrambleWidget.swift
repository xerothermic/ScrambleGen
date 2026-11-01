import AppIntents
import SwiftUI
import WidgetKit

// Watch-face complication: shows the chosen puzzle and, when tapped, opens
// the app on that puzzle (scramblegen://puzzle/<slug>) or on the Timer card
// (scramblegen://timer), handled by ContentView.onOpenURL. Puzzle, its colours
// and the URL format are shared with the app via ScrambleGenerator.swift and
// PuzzleStyle.swift.

// MARK: - Intent

extension ComplicationTarget: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Puzzle" }
    static var caseDisplayRepresentations: [ComplicationTarget: DisplayRepresentation] {
        [.cube3x3: DisplayRepresentation(title: "3×3"),
         .square1: DisplayRepresentation(title: "Square-1"),
         .timer: DisplayRepresentation(title: "Timer")]
    }
}

struct SelectPuzzleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Scramble" }
    static var description: IntentDescription {
        IntentDescription("Choose which puzzle the complication opens.")
    }

    @Parameter(title: "Puzzle", default: .cube3x3)
    var puzzle: ComplicationTarget

    init() {}
    init(puzzle: ComplicationTarget) { self.puzzle = puzzle }
}

// MARK: - Timeline

struct PuzzleEntry: TimelineEntry {
    let date: Date
    let puzzle: ComplicationTarget
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
        ComplicationTarget.allCases.map {
            AppIntentRecommendation(intent: SelectPuzzleIntent(puzzle: $0),
                                    description: Text($0.name))
        }
    }
}

// MARK: - Art

/// Complication artwork drawn with Canvas paths: an isometric three-face cube
/// for 3x3, a top view of kite (corner) and edge pieces with coloured rims for
/// Square-1, a stopwatch for Timer. Colours are the app's sticker colours (CubeFace.stickerColor);
/// when the system renders the widget tinted or vibrant, the pieces are drawn
/// as separated white cells at three opacities (line art) instead.
struct PuzzleArt: View {
    let puzzle: ComplicationTarget
    let fullColor: Bool

    var body: some View {
        if fullColor {
            Canvas { context, size in
                if let puzzle = puzzle.puzzle {
                    PuzzleArtDrawing.drawColour(&context, puzzle: puzzle, size: size)
                } else {
                    PuzzleArtDrawing.drawTimerColour(&context, size: size)
                }
            }
        } else {
            // Tinted / vibrant rendering flattens colour, so the art is drawn as
            // line art: separated cells, three opacity levels, no black strokes.
            // Only layer 0 is accentable; layers 1 and 2 stay plain white so the
            // luminance differences between them survive the tint.
            ZStack {
                Canvas { context, size in
                    if let puzzle = puzzle.puzzle {
                        PuzzleArtDrawing.drawLine(&context, puzzle: puzzle, size: size, layer: 0)
                    } else {
                        PuzzleArtDrawing.drawTimerLine(&context, size: size, layer: 0)
                    }
                }
                .widgetAccentable()
                Canvas { context, size in
                    if let puzzle = puzzle.puzzle {
                        PuzzleArtDrawing.drawLine(&context, puzzle: puzzle, size: size, layer: 1)
                    } else {
                        PuzzleArtDrawing.drawTimerLine(&context, size: size, layer: 1)
                    }
                }
                Canvas { context, size in
                    if let puzzle = puzzle.puzzle {
                        PuzzleArtDrawing.drawLine(&context, puzzle: puzzle, size: size, layer: 2)
                    } else {
                        PuzzleArtDrawing.drawTimerLine(&context, size: size, layer: 2)
                    }
                }
            }
        }
    }

}

// MARK: - View

struct ScrambleComplicationView: View {
    let entry: PuzzleEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var puzzle: ComplicationTarget { entry.puzzle }
    private var fullColor: Bool { renderingMode == .fullColor }

    private var title: String {
        switch puzzle {
        case .cube3x3: return "3×3 Cube"
        case .square1: return "Square-1"
        case .timer: return "Timer"
        }
    }

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
                PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                    .padding(4)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Watch Scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("Tap to scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryCorner:
            // No fixed size: the art fills whatever the corner slot offers.
            PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                .aspectRatio(1, contentMode: .fit)
                .padding(1)
                .widgetLabel { Text(puzzle.name) }
        case .accessoryInline:
            // Inline complications can only show text and SF Symbols.
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
