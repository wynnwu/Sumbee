import XCTest
@testable import SumbeeKit

/// Playlist enumeration parsing (FR-071), playlist-URL validation, dedup (FR-072), and the input
/// mode (FR-068). The live yt-dlp fetch is IP-specific and not exercised here.
final class PlaylistTests: XCTestCase {

    // MARK: parseFlatPlaylist

    func testParseWellFormed() {
        let out = """
        1|||abc123|||First Video|||https://www.youtube.com/watch?v=abc123
        2|||def456|||Second has a | single pipe|||https://www.youtube.com/watch?v=def456
        """
        let e = YouTubeService.parseFlatPlaylist(out)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].index, 1)
        XCTAssertEqual(e[0].videoID, "abc123")
        XCTAssertEqual(e[0].title, "First Video")
        XCTAssertEqual(e[0].url.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(e[1].videoID, "def456")
        XCTAssertEqual(e[1].title, "Second has a | single pipe")
    }

    func testParseSkipsBlankAndNAAndGarbage() {
        let out = """

        1|||abc|||T|||https://www.youtube.com/watch?v=abc
        NA|||NA|||NA|||NA
        garbage line with no delimiter
        3|||xyz|||Third|||https://www.youtube.com/watch?v=xyz
        """
        let e = YouTubeService.parseFlatPlaylist(out)
        XCTAssertEqual(e.map(\.videoID), ["abc", "xyz"])
    }

    func testParseDerivesWatchURLWhenMissing() {
        let e = YouTubeService.parseFlatPlaylist("1|||abc|||Title|||NA")
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].url.absoluteString, "https://www.youtube.com/watch?v=abc")
    }

    // MARK: validatePlaylist

    func testValidatePlaylistAcceptsPlaylistURLs() {
        XCTAssertNotNil(YouTubeService.validatePlaylist(urlString: "https://youtube.com/playlist?list=PLabc"))
        XCTAssertNotNil(YouTubeService.validatePlaylist(urlString: "https://www.youtube.com/playlist?list=PLabc&si=xyz"))
    }

    func testValidatePlaylistRejectsVideosAndJunk() {
        XCTAssertNil(YouTubeService.validatePlaylist(urlString: "https://www.youtube.com/watch?v=abc"))
        XCTAssertNil(YouTubeService.validatePlaylist(urlString: "https://www.youtube.com/playlist")) // no list id
        XCTAssertNil(YouTubeService.validatePlaylist(urlString: "https://example.com/playlist?list=PLabc"))
        XCTAssertNil(YouTubeService.validatePlaylist(urlString: "not a url"))
    }

    // MARK: InputMode

    func testInputModeDefaultAndCases() {
        XCTAssertEqual(InputMode.allCases.count, 2)
        XCTAssertEqual(InputMode.transcripts.rawValue, "transcripts")
        XCTAssertEqual(InputMode.youtube.rawValue, "youtube")
    }

    // MARK: dedup

    @MainActor
    func testIsVideoSummarizedMatchesBySourceRef() {
        setenv("SUMBEE_SMOKE", "1", 1)   // skip the Keychain read during AppState init (learnings #4)
        let state = AppState()
        let style = SummaryStyle(name: "Research", channel: .youtube, prompt: "", order: 0)
        let asset = Asset(url: URL(fileURLWithPath: "/tmp/Research/v.md"), title: "v",
                          styleName: "Research", sourceRef: "https://www.youtube.com/watch?v=ABC123",
                          format: .markdown)
        let group = StyleGroup(name: "Research", folderURL: URL(fileURLWithPath: "/tmp/Research"), assets: [asset])
        state.library = Library(styles: [style], groups: [group])

        XCTAssertTrue(state.isVideoSummarized(id: "ABC123", inStyle: style))
        XCTAssertFalse(state.isVideoSummarized(id: "ZZZ999", inStyle: style))
    }

    @MainActor
    func testDedupComparesCanonicalIDNotSubstring() {
        setenv("SUMBEE_SMOKE", "1", 1)
        let state = AppState()
        let style = SummaryStyle(name: "S", channel: .youtube, prompt: "", order: 0)
        let asset = Asset(url: URL(fileURLWithPath: "/tmp/S/v.md"), title: "v", styleName: "S",
                          sourceRef: "https://www.youtube.com/watch?v=XYabc123XYZ", format: .markdown)
        state.library = Library(styles: [style],
                                groups: [StyleGroup(name: "S", folderURL: URL(fileURLWithPath: "/tmp/S"), assets: [asset])])
        XCTAssertTrue(state.isVideoSummarized(id: "XYabc123XYZ", inStyle: style))  // exact canonical id
        XCTAssertFalse(state.isVideoSummarized(id: "abc123", inStyle: style))      // substring must not match
    }
}
