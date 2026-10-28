import XCTest
import CoreGraphics
@testable import ZoomiesCore

final class SpriteLayoutTests: XCTestCase {
    func testOriginalAtlasCellsKeepTheirAspectAndRowOrder() throws {
        let layout = try SpriteLayout(width: 1536, height: 2288)
        XCTAssertEqual(layout.cellWidth, 192)
        XCTAssertEqual(layout.cellHeight, 208)
        XCTAssertEqual(try layout.frameRect(state: .runningRight, index: 0), CGRect(x: 0, y: 208, width: 192, height: 208))
        XCTAssertEqual(try layout.frameRect(state: .runningLeft, index: 7), CGRect(x: 1344, y: 416, width: 192, height: 208))
    }

    func testOnlyAuthoredFramesAreUsed() throws {
        let layout = try SpriteLayout(width: 1536, height: 2288)
        XCTAssertEqual(SpriteLayout.State.idle.frameCount, 6)
        XCTAssertEqual(SpriteLayout.State.runningRight.frameCount, 8)
        XCTAssertEqual(SpriteLayout.State.runningLeft.frameCount, 8)
        XCTAssertThrowsError(try layout.frameRect(state: .idle, index: 6))
        XCTAssertThrowsError(try layout.frameRect(state: .runningLeft, index: -1))
        XCTAssertThrowsError(try layout.frameRect(state: .runningRight, index: 8))
    }

    func testMalformedOrOversizedImagesAreRejectedBeforeDecoding() {
        for (width, height) in [(0, 0), (1535, 2288), (1536, 2287), (8192, 11264)] {
            XCTAssertThrowsError(try SpriteLayout(width: width, height: height))
        }
    }

    func testEveryFrameStaysInsideItsOwnCell() throws {
        let layout = try SpriteLayout(width: 1536, height: 2288)
        for state in SpriteLayout.State.allCases {
            for index in 0..<state.frameCount {
                let rect = try layout.frameRect(state: state, index: index)
                XCTAssertEqual(rect.minX, CGFloat(index * 192))
                XCTAssertEqual(rect.minY, CGFloat(state.row * 208))
                XCTAssertLessThanOrEqual(rect.maxX, 1536)
                XCTAssertEqual(rect.maxY, CGFloat((state.row + 1) * 208))
            }
        }
    }
}
