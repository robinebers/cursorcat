import AppKit
import CoreGraphics

/// Cat animation state modes. Frame index is chosen inside `CatAnimator`.
enum CatState: Equatable {
    case idle
    case alert
    case tired
    case sleeping
    case scratching
    case error
}

/// Extracts individual 32x32 frames from `oneko.gif` (adryd325/oneko.js, MIT)
/// and returns them as full-colour `NSImage`s (white body + black outline +
/// transparent background, exactly as authored). Rendered as non-template so
/// the body/outline/detail shading survives the menu bar.
enum CatRenderer {
    /// Source sheet layout: 8 columns × 4 rows of 32×32 sprites.
    private static let cell = 32
    private static let sheetCols = 8
    private static let sheetRows = 4

    /// Point size used in the menu bar (scaled 1:1 from 32×32 px).
    static let imageSize = NSSize(width: 22, height: 22)

    /// Sprite cells taken directly from `adryd325/oneko.js` (column, row).
    /// The sprite sheet is laid out as an 8×4 grid; the adryd325 source uses
    /// negative CSS background-position offsets which we invert here.
    enum Cell {
        static let idle = (3, 3)
        static let alert = (7, 3)
        static let tired = (3, 2)
        static let sleeping = [(2, 0), (2, 1)]
        static let scratchSelf = [(5, 0), (6, 0), (7, 0)]

        // 8 compass-direction running sprites, 2 frames each.
        static let runN  = [(1, 2), (1, 3)]
        static let runNE = [(0, 2), (0, 3)]
        static let runE  = [(3, 0), (3, 1)]
        static let runSE = [(5, 1), (5, 2)]
        static let runS  = [(6, 3), (7, 2)]
        static let runSW = [(5, 3), (6, 1)]
        static let runW  = [(4, 2), (4, 3)]
        static let runNW = [(1, 0), (1, 1)]

        /// Clockwise run-around: N → NE → E → SE → S → SW → W → NW.
        /// Flattened 2-per-direction = 16 frames total.
        static let runAround: [(Int, Int)] = [
            runN, runNE, runE, runSE, runS, runSW, runW, runNW
        ].flatMap { $0 }
    }

    @MainActor
    private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(for cell: (Int, Int)) -> NSImage {
        let key = "\(cell.0),\(cell.1)"
        if let cached = cache[key] { return cached }
        let img = extractSprite(col: cell.0, row: cell.1)
        cache[key] = img
        return img
    }

    // MARK: - Sheet loading

    @MainActor
    private static let sheetBitmap: NSBitmapImageRep? = {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "oneko", withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data)
        else {
            Log.ui.error("CatRenderer: failed to load oneko.gif from bundle")
            return nil
        }
        return rep
    }()

    /// Crop the 32×32 sprite at (col, row) from the sheet and upscale 2× with
    /// point-sampling so pixels stay crisp. Preserves source RGBA — the white
    /// body, black outline, and transparent background all survive.
    @MainActor
    private static func extractSprite(col: Int, row: Int) -> NSImage {
        let pxScale = 2
        let bufferSide = cell * pxScale
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: bufferSide,
            height: bufferSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: imageSize)
        }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none

        guard let sheet = sheetBitmap else {
            return NSImage(size: imageSize)
        }

        let baseX = col * cell
        let baseY = row * cell

        for yInCell in 0..<cell {
            for xInCell in 0..<cell {
                guard let color = sheet.colorAt(x: baseX + xInCell, y: baseY + yInCell),
                      color.alphaComponent > 0
                else { continue }
                // Flip Y — CGContext origin is bottom-left.
                let dstY = (cell - 1 - yInCell) * pxScale
                let dstX = xInCell * pxScale
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: dstX, y: dstY, width: pxScale, height: pxScale))
            }
        }

        guard let cg = ctx.makeImage() else { return NSImage(size: imageSize) }
        let image = NSImage(cgImage: cg, size: imageSize)
        image.isTemplate = false
        return image
    }
}
