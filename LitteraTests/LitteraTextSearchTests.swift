import AppKit
import XCTest
@testable import Littera

@MainActor
final class LitteraTextSearchTests: XCTestCase {
    func testMatchesIgnoreCaseAndDiacritics() {
        let text = "Canción, cancion y CANCIÓN."
        XCTAssertEqual(
            LitteraTextSearch.matches(of: "cancion", in: text),
            [NSRange(location: 0, length: 7), NSRange(location: 9, length: 7), NSRange(location: 19, length: 7)]
        )
    }

    func testEmptyQueryHasNoMatches() {
        XCTAssertTrue(LitteraTextSearch.matches(of: "", in: "texto").isEmpty)
        XCTAssertTrue(LitteraTextSearch.matches(of: "x", in: "").isEmpty)
    }

    func testOverlappingQueriesDoNotLoop() {
        XCTAssertEqual(LitteraTextSearch.matches(of: "aa", in: "aaaa").count, 2)
    }

    func testNextWrapsAround() {
        let matches = LitteraTextSearch.matches(of: "a", in: "a b a b a")
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: matches[0], direction: .next), 1)
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: matches[2], direction: .next), 0)
    }

    func testPreviousWrapsAround() {
        let matches = LitteraTextSearch.matches(of: "a", in: "a b a b a")
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: matches[1], direction: .previous), 0)
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: matches[0], direction: .previous), 2)
    }

    func testIncrementalKeepsMatchAtSelection() {
        let matches = LitteraTextSearch.matches(of: "ab", in: "xx ab ab")
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: NSRange(location: 3, length: 1), direction: .incremental), 0)
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: NSRange(location: 7, length: 0), direction: .incremental), 0)
        XCTAssertEqual(LitteraTextSearch.index(in: matches, selection: NSRange(location: 4, length: 0), direction: .incremental), 1)
    }
}

@MainActor
final class LitteraReplaceTests: XCTestCase {
    private func makeTarget(_ text: String) -> (LitteraEditingTarget, NSTextView) {
        let textView = LitteraEditorTextView()
        textView.string = text
        let target = LitteraEditingTarget()
        target.register(textView)
        return (target, textView)
    }

    func testReplaceAllReplacesEveryMatch() {
        let (target, textView) = makeTarget("Canción, cancion y CANCIÓN.")
        XCTAssertEqual(target.replaceAll("cancion", with: "tema"), 3)
        XCTAssertEqual(textView.string, "tema, tema y tema.")
    }

    func testReplaceCurrentOnlyReplacesSelectedMatch() {
        let (target, textView) = makeTarget("uno dos uno")
        XCTAssertEqual(target.search("uno", direction: .incremental), LitteraSearchResult(current: 1, total: 2))
        let result = target.replaceCurrent("uno", with: "1")
        XCTAssertEqual(textView.string, "1 dos uno")
        XCTAssertEqual(result, LitteraSearchResult(current: 1, total: 1))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 3))
    }

    func testReplaceCurrentWithoutMatchSelectedOnlyMoves() {
        let (target, textView) = makeTarget("a uno")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        _ = target.replaceCurrent("uno", with: "1")
        XCTAssertEqual(textView.string, "a uno")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 3))
    }
}
