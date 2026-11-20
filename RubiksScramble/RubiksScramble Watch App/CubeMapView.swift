import SwiftUI
import WatchKit

/// 2D unfolded "net" of the cube after the scramble is applied:
///
///         U
///     L   F   R   B
///         D
struct CubeMapView: View {
    let moves: [String]

    /// Sticker size, shrunk to fit the screen width: the net is 4 faces wide, so
    /// width = 4*(3*cell + 2*gap) + 3*faceGap + 2*padding. With 10 pt spare
    /// for the screen edge: 40 mm (162 pt) -> 10, 41 mm (176) -> 11,
    /// 44 mm (184) -> 12, 45 mm (198) and up -> 13 (the old fixed size).
    private var cell: CGFloat {
        let screen = WKInterfaceDevice.current().screenBounds.width
        let fixed = 4 * 2 * stickerGap + 3 * faceGap + 12
        return min(13, max(6, ((screen - 10 - fixed) / 12).rounded(.down)))
    }
    private let stickerGap: CGFloat = 1
    private let faceGap: CGFloat = 3

    private var faceSide: CGFloat { cell * 3 + stickerGap * 2 }

    var body: some View {
        let cube = CubeState.scrambled(by: moves)
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: faceGap) {
                    row(cube, [nil, .up, nil, nil])
                    row(cube, [.left, .front, .right, .back])
                    row(cube, [nil, .down, nil, nil])
                }
                .padding(6)
                .frame(maxWidth: .infinity)
            }
            .modifier(CloseAwareTitle(title: "Cube"))
            .hidingTime()
        }
    }

    private func row(_ cube: CubeState, _ faces: [CubeFace?]) -> some View {
        HStack(spacing: faceGap) {
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                if let face {
                    faceGrid(cube, face)
                } else {
                    Color.clear.frame(width: faceSide, height: faceSide)
                }
            }
        }
    }

    private func faceGrid(_ cube: CubeState, _ face: CubeFace) -> some View {
        VStack(spacing: stickerGap) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: stickerGap) {
                    ForEach(0..<3, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cube.color(face: face, row: r, col: c))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}

#Preview {
    CubeMapView(moves: ScrambleGenerator.generate())
}
