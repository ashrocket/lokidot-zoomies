import XCTest
@testable import ZoomiesCore

final class MeetingLinkTests: XCTestCase {
    private func find(_ text: String) -> String? {
        MeetingLink.find(in: [text])?.absoluteString
    }

    private func provider(_ text: String) -> String? {
        guard let url = URL(string: text) else { return nil }
        return MeetingLink.provider(for: url)
    }

    func testTrailingPunctuationIsTrimmedFromZoomJoinLink() {
        XCTAssertEqual(find("Join: https://us02web.zoom.us/j/123456789?pwd=abc."),
                       "https://us02web.zoom.us/j/123456789?pwd=abc")
        XCTAssertEqual(provider("https://us02web.zoom.us/j/123456789?pwd=abc"), "Zoom")
    }

    func testZoomPathsAndBareHosts() {
        XCTAssertEqual(provider("https://zoom.us/my/ashroom"), "Zoom")
        XCTAssertEqual(provider("https://zoomgov.com/j/1"), "Zoom")
        XCTAssertNil(provider("https://zoom.us"))
        XCTAssertNil(provider("https://zoom.us/download"))
    }

    func testGoogleMeetInsideHTMLAnchor() {
        XCTAssertEqual(find("<a href=\"https://meet.google.com/abc-defg-hij\">Join</a>"),
                       "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(provider("https://meet.google.com/abc-defg-hij"), "Google Meet")
        XCTAssertNil(provider("https://meet.google.com/"))
    }

    func testTeamsMeetupJoinIsReturnedIntact() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%7d"
        XCTAssertEqual(find(link), link)
        XCTAssertEqual(provider(link), "Microsoft Teams")
        XCTAssertEqual(provider("https://teams.live.com/meet/9123"), "Microsoft Teams")
    }

    func testWebexPaths() {
        XCTAssertEqual(provider("https://acme.webex.com/acme/j.php?MTID=m123"), "Webex")
        XCTAssertEqual(provider("https://acme.webex.com/meet/ash"), "Webex")
    }

    func testSafeLinksAreUnwrapped() {
        XCTAssertEqual(find("https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fus02web.zoom.us%2Fj%2F999&data=x"),
                       "https://us02web.zoom.us/j/999")
    }

    func testGoogleRedirectIsUnwrapped() {
        XCTAssertEqual(find("https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D"),
                       "https://meet.google.com/abc-defg-hij")
    }

    func testFirstRecognisedLinkInTextWins() {
        XCTAssertEqual(find("Agenda https://docs.google.com/doc/1 then https://meet.google.com/abc-defg-hij"),
                       "https://meet.google.com/abc-defg-hij")
    }

    func testFindScansTextsInOrderSkippingNil() {
        XCTAssertEqual(MeetingLink.find(in: [nil, "no links", "https://zoom.us/j/1"])?.absoluteString,
                       "https://zoom.us/j/1")
        XCTAssertEqual(MeetingLink.find(in: ["https://zoom.us/j/1", "https://meet.google.com/abc-defg-hij"])?.absoluteString,
                       "https://zoom.us/j/1")
        XCTAssertNil(MeetingLink.find(in: [nil, "no links"]))
    }

    func testRejectsNonHTTPSAndLookalikeHosts() {
        XCTAssertNil(find("http://zoom.us/j/1"))
        XCTAssertNil(find("https://zoom.us.evil.com/j/1"))
        XCTAssertNil(find("https://evilzoom.us/j/1"))
    }

    func testChimeWherebyJitsiHuddleFaceTimeGoToAndBlueJeans() {
        XCTAssertEqual(provider("https://chime.aws/1234567890"), "Amazon Chime")
        XCTAssertEqual(provider("https://whereby.com/ashroom"), "Whereby")
        XCTAssertEqual(provider("https://meet.jit.si/standup"), "Jitsi Meet")
        XCTAssertEqual(provider("https://app.slack.com/huddle/T1/C1"), "Slack Huddle")
        XCTAssertEqual(provider("https://facetime.apple.com/join#v=1&p=abc"), "FaceTime")
        XCTAssertEqual(provider("https://meet.goto.com/123456789"), "GoTo Meeting")
        XCTAssertEqual(provider("https://global.gotomeeting.com/join/123"), "GoTo Meeting")
        XCTAssertEqual(provider("https://bluejeans.com/123"), "BlueJeans")
    }

    func testAmpersandEntityBecomesAmpersand() {
        XCTAssertEqual(find("https://zoom.us/j/7?pwd=a&amp;uname=b"),
                       "https://zoom.us/j/7?pwd=a&uname=b")
    }

    func testTrailingParenthesisIsTrimmed() {
        XCTAssertEqual(find("(https://zoom.us/j/5)"), "https://zoom.us/j/5")
    }
}
