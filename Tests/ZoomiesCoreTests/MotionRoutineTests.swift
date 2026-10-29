import XCTest
import CoreGraphics
@testable import ZoomiesCore

final class MotionRoutineTests: XCTestCase {
    func testAllRoutinesStayInsideSmallPortraitAndOffsetDisplays() {
        for bounds in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -900, y: 80, width: 900, height: 1600),
                       CGRect(x: 0, y: 0, width: 320, height: 200),
                       CGRect(x: 0, y: 0, width: 80, height: 80)] {
            for style in MotionStyle.allCases {
                for index in 0..<3 {
                    let routine = MotionRoutine(style: style, bounds: bounds, index: index, count: 3)
                    let size = routine.route.spriteSize
                    for step in 0...1800 {
                        let pose = routine.sample(progress: Double(step) / 1800)
                        let halfW = (abs(cos(pose.bank)) * size.width * pose.scaleX + abs(sin(pose.bank)) * size.height * pose.scaleY) / 2
                        let halfH = (abs(sin(pose.bank)) * size.width * pose.scaleX + abs(cos(pose.bank)) * size.height * pose.scaleY) / 2
                        XCTAssertGreaterThanOrEqual(pose.point.x - halfW, bounds.minX)
                        XCTAssertLessThanOrEqual(pose.point.x + halfW, bounds.maxX)
                        XCTAssertGreaterThanOrEqual(pose.point.y - halfH, bounds.minY)
                        XCTAssertLessThanOrEqual(pose.point.y + halfH, bounds.maxY)
                        XCTAssertGreaterThan(pose.scaleX, 0.60, "A turn must not make a dog disappear")
                        XCTAssertLessThan(abs(pose.bank), 0.4, "Dogs stay upright")
                    }
                }
            }
        }
    }

    func testRoutinesCloseWithoutTeleportingOrEndpointVelocity() {
        for style in MotionStyle.allCases {
            for index in 0..<3 {
                let routine = MotionRoutine(style: style, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900), index: index, count: 3)
                let first = routine.sample(progress: 0), last = routine.sample(progress: 1)
                XCTAssertEqual(first.point.x, last.point.x, accuracy: 1e-6)
                XCTAssertEqual(first.point.y, last.point.y, accuracy: 1e-6)
                for (a, b) in [(first, routine.sample(progress: 0.0001)), (last, routine.sample(progress: 0.9999))] {
                    XCTAssertLessThan(hypot(a.point.x - b.point.x, a.point.y - b.point.y), 0.02)
                }
            }
        }
    }

    func testCircleIsCompactAndCrossfadesBothAuthoredDirections() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let routine = MotionRoutine(style: .circle, bounds: bounds)
        var left = false, right = false, blend = false
        for step in 0...1000 {
            let pose = routine.sample(progress: Double(step) / 1000)
            XCTAssertLessThanOrEqual(abs(pose.point.x - bounds.midX), 180.01)
            XCTAssertLessThanOrEqual(abs(pose.point.y - bounds.midY), 64.01)
            left = left || pose.rightWeight < 0.01
            right = right || pose.rightWeight > 0.99
            blend = blend || (0.2...0.8).contains(pose.rightWeight)
        }
        XCTAssertTrue(left && right && blend)
    }

    func testPranceHasSixGroundedHopsAndUsesJumpPoses() {
        let routine = MotionRoutine(style: .prance, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let floor = routine.sample(progress: 0).point.y
        for hop in 0..<6 {
            let landing = routine.sample(progress: Double(hop) / 6)
            let apex = routine.sample(progress: (Double(hop) + 0.5) / 6)
            XCTAssertEqual(landing.point.y, floor, accuracy: 1e-6)
            XCTAssertGreaterThan(apex.point.y, floor + 20)
            XCTAssertNotNil(apex.jumpProgress)
        }
    }

    func testInvalidProgressAndGroupIndicesAreSafe() {
        for style in MotionStyle.allCases {
            let routine = MotionRoutine(style: style, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), index: -1, count: 0)
            XCTAssertEqual(routine.index, 0); XCTAssertEqual(routine.count, 1)
            XCTAssertEqual(routine.sample(progress: .nan).point, routine.sample(progress: 0).point)
            XCTAssertEqual(routine.sample(progress: -.infinity).point, routine.sample(progress: 0).point)
            XCTAssertEqual(routine.sample(progress: 2).point, routine.sample(progress: 1).point)
        }
    }
}
