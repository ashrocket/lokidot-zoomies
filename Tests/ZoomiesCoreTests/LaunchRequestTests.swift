import XCTest
@testable import ZoomiesCore

final class LaunchRequestTests: XCTestCase {
    func testEveryActionAndMotionRoundTrips() throws {
        for action in [LaunchRequest.Action.show, .play, .pause, .resume, .quit] {
            let request = try LaunchRequest(action: action)
            XCTAssertEqual(try LaunchRequest(url: request.url), request)
        }
        for style in MotionStyle.allCases {
            let request = try LaunchRequest(action: .play, motion: style, character: "all")
            XCTAssertEqual(try LaunchRequest(url: request.url), request)
        }
    }

    func testDogPathsWithSpacesUnicodeAndQueryCharactersStayLocal() throws {
        let path = "/Users/me/My Dogs/Biscuit & Zoë #1? lovely"
        let request = try LaunchRequest(action: .play, motion: .circle, packPath: path)
        XCTAssertEqual(try LaunchRequest(url: request.url).packPath, path)
    }

    func testRejectsUnknownDuplicateAndExecutableOptions() {
        for url in ["https://control/play", "lokidot://control/exec?command=rm",
                    "lokidot://control/play?motion=flight", "lokidot://control/play?motion=circle&motion=prance",
                    "lokidot://control/play?pack=https%3A%2F%2Fexample.com", "lokidot://control/show?pack=relative",
                    "lokidot://user@control/play", "lokidot://control/play#commands",
                    "lokidot://control/play?diagnostics=/tmp/report", "lokidot://control/play?character=",
                    "lokidot://control/quit?character=all"] {
            XCTAssertThrowsError(try LaunchRequest(url: URL(string: url)!), url)
        }
    }

    func testRejectsAmbiguousSelectionAndInvalidPaths() {
        XCTAssertThrowsError(try LaunchRequest(character: "all", packPath: "/tmp/dog"))
        XCTAssertThrowsError(try LaunchRequest(character: "../dog"))
        XCTAssertThrowsError(try LaunchRequest(packPath: "/tmp/dog\nfile"))
    }
}
