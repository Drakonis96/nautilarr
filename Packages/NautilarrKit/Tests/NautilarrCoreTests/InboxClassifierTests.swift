import XCTest
@testable import NautilarrCore

final class InboxClassifierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func download(
        id: String = "d1", type: ServiceType = .qbittorrent, name: String = "Thing",
        isClient: Bool = true, category: String = "downloading", state: String = "downloading",
        warning: Bool = false, error: Bool = false, paused: Bool = false,
        speed: Int? = nil, progress: Double = 0.5
    ) -> InboxDownloadSnapshot {
        InboxDownloadSnapshot(id: id, serviceType: type, instanceName: "inst", title: name,
                              isDownloadClient: isClient, category: category, state: state,
                              isWarning: warning, isError: error, isPaused: paused,
                              downloadSpeed: speed, progress: progress)
    }

    private func health(id: String = "h1", severity: InboxSeverity = .warning) -> InboxHealthSnapshot {
        InboxHealthSnapshot(id: id, serviceType: .sonarr, instanceName: "inst",
                            message: "Indexer unavailable", severity: severity, wikiURL: "https://wiki")
    }

    // MARK: Stall detection

    func testZeroSpeedBelowThresholdIsNotYetStuckButTracked() {
        let d = download(speed: 0)
        let (issues, stall) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertTrue(issues.isEmpty, "should not flag until threshold elapses")
        XCTAssertEqual(stall["d1"], now, "but the stall start is recorded")
    }

    func testZeroSpeedPastThresholdIsStuck() {
        let started = now.addingTimeInterval(-2000)   // 33min ago
        let d = download(speed: 0)
        let (issues, stall) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: ["d1": started], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .stuckDownload)
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(stall["d1"], started, "carried forward while still stalling")
    }

    func testSpeedRecoveryClearsStall() {
        let d = download(speed: 50_000)
        let (issues, stall) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: ["d1": now.addingTimeInterval(-9999)],
            now: now, stallThreshold: 1800)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertNil(stall["d1"], "moving again drops it from the stall map")
    }

    func testPausedItemIsNeverStuck() {
        let d = download(paused: true, speed: 0)
        let (issues, stall) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: ["d1": now.addingTimeInterval(-9999)],
            now: now, stallThreshold: 1800)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertNil(stall["d1"])
    }

    func testUnknownSpeedIsNotFlagged() {
        // nil speed (source doesn't report it) must not produce false positives.
        let d = download(speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: Errors & imports

    func testErroredClientItemIsAlwaysError() {
        let d = download(category: "error", state: "missingFiles", error: true, speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .stuckDownload)
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testArrWarningIsFailedImportWarning() {
        let d = download(id: "a1", type: .sonarr, isClient: false, state: "importPending", warning: true, speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .failedImport)
        XCTAssertEqual(issues.first?.severity, .warning)
    }

    func testArrImportBlockedStateFlaggedEvenWithoutWarningFlag() {
        let d = download(id: "a1", type: .radarr, isClient: false, state: "importBlocked", speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.first?.kind, .failedImport)
    }

    func testArrErrorIsFailedImportError() {
        let d = download(id: "a1", type: .sonarr, isClient: false, state: "failed", error: true, speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testHealthyArrDownloadingItemIsNotFlagged() {
        let d = download(id: "a1", type: .sonarr, isClient: false, state: "downloading", speed: nil)
        let (issues, _) = InboxClassifier.classify(
            downloads: [d], health: [], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: Health + ordering

    func testHealthBecomesIssueWithWiki() {
        let (issues, _) = InboxClassifier.classify(
            downloads: [], health: [health(severity: .error)], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .health)
        XCTAssertEqual(issues.first?.wikiURL, "https://wiki")
    }

    func testIssuesSortedBySeverityDescending() {
        let warnDownload = download(id: "a1", type: .sonarr, isClient: false, warning: true, speed: nil)
        let errHealth = health(id: "h9", severity: .error)
        let (issues, _) = InboxClassifier.classify(
            downloads: [warnDownload], health: [errHealth], stallSince: [:], now: now, stallThreshold: 1800)
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.first?.severity, .error, "error sorts before warning")
        XCTAssertEqual(issues.last?.severity, .warning)
    }

    func testSeverityFromHealthMapping() {
        XCTAssertEqual(InboxSeverity.fromHealth("error"), .error)
        XCTAssertEqual(InboxSeverity.fromHealth("Warning"), .warning)
        XCTAssertEqual(InboxSeverity.fromHealth("notice"), .notice)
        XCTAssertNil(InboxSeverity.fromHealth("ok"))
        XCTAssertNil(InboxSeverity.fromHealth(nil))
    }
}
