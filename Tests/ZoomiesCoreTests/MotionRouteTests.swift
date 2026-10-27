import XCTest
import CoreGraphics
@testable import ZoomiesCore

final class MotionRouteTests: XCTestCase {
    func testEveryPoseFitsDisplayIncludingRotatedArtwork() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 875),
                       CGRect(x: -1920, y: 150, width: 1920, height: 1055),
                       CGRect(x: 1440, y: -900, width: 900, height: 1600),
                       CGRect(x: 0, y: 0, width: 320, height: 200),
                       CGRect(x: 0, y: 0, width: 80, height: 80)]
        for screen in screens {
            let route = MotionRoute(bounds: screen)
            let radius = hypot(route.spriteSize.width, route.spriteSize.height) / 2
            for i in 0...6000 {
                let point = route.sample(progress: Double(i) / 6000).point
                XCTAssertGreaterThanOrEqual(point.x - radius, screen.minX)
                XCTAssertLessThanOrEqual(point.x + radius, screen.maxX)
                XCTAssertGreaterThanOrEqual(point.y - radius, screen.minY)
                XCTAssertLessThanOrEqual(point.y + radius, screen.maxY)
            }
        }
    }

    func testClosedLapHasContinuousHeading() {
        let route = MotionRoute(bounds: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let start = route.sample(distanceFraction: 0)
        let end = route.sample(distanceFraction: 1)
        XCTAssertEqual(start.point.x, end.point.x, accuracy: 0.0001)
        XCTAssertEqual(start.point.y, end.point.y, accuracy: 0.0001)
        XCTAssertEqual(start.tangent.dx, end.tangent.dx, accuracy: 0.0001)
        XCTAssertEqual(start.tangent.dy, end.tangent.dy, accuracy: 0.0001)
        XCTAssertLessThan(start.tangent.dx, 0, "The lap must start to the left")
    }

    func testStartsLeftThenDipsAndRunsRight() {
        let route = MotionRoute(bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let initial = route.sample(distanceFraction: 0)
        let left = route.sample(distanceFraction: 0.12)
        let right = route.sample(distanceFraction: 0.25)
        XCTAssertLessThan(left.point.x, initial.point.x)
        XCTAssertLessThan(right.point.y, initial.point.y)
        XCTAssertGreaterThan(right.tangent.dx, 0)
    }

    func testArcLengthSamplingAvoidsSegmentSpeedJumps() {
        let route = MotionRoute(bounds: CGRect(x: 0, y: 0, width: 1600, height: 900))
        let expected = route.length / 4000
        var previous = route.sample(distanceFraction: 0).point
        for i in 1...4000 {
            let point = route.sample(distanceFraction: Double(i) / 4000).point
            let distance = hypot(point.x - previous.x, point.y - previous.y)
            XCTAssertEqual(distance, expected, accuracy: expected * 0.06)
            previous = point
        }
    }

    func testAccelerationIsMonotonicAndSettlesAtBothEnds() {
        var previous = 0.0
        for i in 0...10000 {
            let current = MotionRoute.distanceProgress(Double(i) / 10000)
            XCTAssertGreaterThanOrEqual(current, previous)
            previous = current
        }
        XCTAssertEqual(MotionRoute.distanceProgress(0), 0, accuracy: 1e-10)
        XCTAssertEqual(MotionRoute.distanceProgress(1), 1, accuracy: 1e-10)
        XCTAssertLessThan(MotionRoute.distanceProgress(0.001), 0.00001)
        XCTAssertLessThan(1 - MotionRoute.distanceProgress(0.999), 0.00001)
    }

    func testHeadingIsFiniteAndContinuousAcrossVerticalTurns() {
        let route = MotionRoute(bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var previous = MotionRoute.orientation(route.sample(distanceFraction: 0).tangent)
        for i in 1...10000 {
            let pose = MotionRoute.orientation(route.sample(distanceFraction: Double(i) / 10000).tangent)
            XCTAssertTrue(pose.facing.isFinite && pose.bank.isFinite)
            XCTAssertLessThan(abs(pose.facing - previous.facing), 0.15)
            XCTAssertLessThan(abs(pose.bank - previous.bank), 0.15)
            previous = pose
        }
    }

    func testInvalidProgressClampsSafely() {
        let route = MotionRoute(bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(route.sample(progress: -1).point, route.sample(progress: 0).point)
        XCTAssertEqual(route.sample(progress: 2).point, route.sample(progress: 1).point)
        XCTAssertEqual(route.sample(progress: .nan).point, route.sample(progress: 0).point)
    }
}
