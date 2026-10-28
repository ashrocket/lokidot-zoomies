import Foundation
import CoreGraphics

/// The original pet atlas is eight columns by eleven rows. Coordinates are
/// measured from the image's top-left corner, as used by CGImage cropping.
public struct SpriteLayout {
    public enum State: CaseIterable {
        case idle, runningRight, runningLeft
        public var row: Int {
            switch self { case .idle: return 0; case .runningRight: return 1; case .runningLeft: return 2 }
        }
        public var frameCount: Int { self == .idle ? 6 : 8 }
    }
    public enum Error: Swift.Error, LocalizedError {
        case invalidDimensions, invalidFrame
        public var errorDescription: String? {
            switch self {
            case .invalidDimensions: return "Choose an eight-column, eleven-row pet PNG (for example, 1536 × 2288)."
            case .invalidFrame: return "The requested animation frame is outside this row."
            }
        }
    }
    public let width: Int
    public let height: Int
    public var cellWidth: Int { width / 8 }
    public var cellHeight: Int { height / 11 }
    public init(width: Int, height: Int) throws {
        guard width >= 8, height >= 11, width <= 4096, height <= 8192,
              width % 8 == 0, height % 11 == 0 else { throw Error.invalidDimensions }
        self.width = width
        self.height = height
    }
    public func frameRect(state: State, index: Int) throws -> CGRect {
        guard (0..<state.frameCount).contains(index) else { throw Error.invalidFrame }
        return CGRect(x: index * cellWidth, y: state.row * cellHeight,
                      width: cellWidth, height: cellHeight)
    }
}
