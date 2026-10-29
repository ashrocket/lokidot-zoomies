import XCTest

@main
enum TestRunner {
    static func main() {
        let suite = XCTestSuite(name: "LokiDotZoomies")
        suite.addTest(MotionRouteTests.defaultTestSuite)
        suite.addTest(SpritePackTests.defaultTestSuite)
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0 else { exit(2) }
        exit(result.hasSucceeded ? 0 : 1)
    }
}
