import XCTest
@testable import NautilarrCore

final class PipelineCorrelatorTests: XCTestCase {
    private func match(_ progress: Double, _ state: String, error: Bool = false) -> PipelineQueueMatch {
        PipelineQueueMatch(progress: progress, trackedState: state, hasError: error)
    }

    // MARK: stage()

    func testPendingApprovalIsRequested() {
        let r = PipelineCorrelator.stage(requestStatus: 1, mediaStatus: 2, match: nil)
        XCTAssertEqual(r.stage, .requested)
    }

    func testApprovedNoQueueIsApproved() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 2, match: nil)
        XCTAssertEqual(r.stage, .approved)
    }

    func testApprovedProcessingNoQueueIsGrabbed() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 3, match: nil)
        XCTAssertEqual(r.stage, .grabbed)
    }

    func testQueueWithProgressIsDownloading() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 3, match: match(0.42, "downloading"))
        XCTAssertEqual(r.stage, .downloading)
        XCTAssertEqual(r.progress, 0.42, accuracy: 0.001)
    }

    func testQueueZeroProgressIsGrabbed() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 3, match: match(0, "queued"))
        XCTAssertEqual(r.stage, .grabbed)
    }

    func testImportStateIsImporting() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 3, match: match(1.0, "importPending"))
        XCTAssertEqual(r.stage, .importing)
    }

    func testCompletedDownloadIsImporting() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 3, match: match(1.0, "downloading"))
        XCTAssertEqual(r.stage, .importing)
    }

    func testAvailableTrumpsEverything() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 5, match: match(0.3, "downloading"))
        XCTAssertEqual(r.stage, .available)
        XCTAssertEqual(r.progress, 1)
    }

    func testPartiallyAvailableNoQueueIsAvailable() {
        let r = PipelineCorrelator.stage(requestStatus: 2, mediaStatus: 4, match: nil)
        XCTAssertEqual(r.stage, .available)
    }

    // MARK: best()

    func testBestPrefersImporting() {
        let best = PipelineQueueMatch.best([match(0.9, "downloading"), match(0.2, "importPending")])
        XCTAssertEqual(best?.trackedState, "importPending")
    }

    func testBestPicksHighestProgressWhenNoImport() {
        let best = PipelineQueueMatch.best([match(0.2, "downloading"), match(0.8, "downloading")])
        XCTAssertEqual(best?.progress, 0.8)
    }

    func testBestOfEmptyIsNil() {
        XCTAssertNil(PipelineQueueMatch.best([]))
    }

    // MARK: visibility & match key

    func testDeclinedIsHidden() {
        XCTAssertFalse(PipelineCorrelator.isVisible(requestStatus: 3))
        XCTAssertTrue(PipelineCorrelator.isVisible(requestStatus: 1))
        XCTAssertTrue(PipelineCorrelator.isVisible(requestStatus: 2))
    }

    func testMatchKeyNormalisesTitleAndYear() {
        XCTAssertEqual(PipelineCorrelator.matchKey(title: "The Matrix!", year: 1999), "thematrix#1999")
        XCTAssertEqual(PipelineCorrelator.matchKey(title: "WALL·E", year: 2008), "walle#2008")
        XCTAssertEqual(PipelineCorrelator.matchKey(title: "Dune", year: nil), "dune")
    }

    func testStagesAreOrdered() {
        XCTAssertTrue(PipelineStage.requested < PipelineStage.available)
        XCTAssertEqual(PipelineStage.allCases.count, 6)
    }
}
