import FamilyControls
import XCTest

@testable import foqos

final class AppCountdownTests: XCTestCase {
  private let suite = UserDefaults(suiteName: "group.dev.ambitionsoftware.foqos")!
  private let issuedAt = Date(timeIntervalSince1970: 1_000_000)
  private let profileId = UUID()

  override func setUp() {
    super.setUp()
    removeStoredPasses()
  }

  override func tearDown() {
    removeStoredPasses()
    super.tearDown()
  }

  // MARK: - Launch pass

  func testIssuedPassIsConsumedOnce() {
    AppCountdownLaunchPassStore.issue(for: "Messages", at: issuedAt)

    XCTAssertTrue(
      AppCountdownLaunchPassStore.consume(for: "Messages", at: issuedAt.addingTimeInterval(1)))
    XCTAssertFalse(
      AppCountdownLaunchPassStore.consume(for: "Messages", at: issuedAt.addingTimeInterval(2)))
  }

  func testPassExpiresFifteenSecondsAfterIssue() {
    AppCountdownLaunchPassStore.issue(for: "Messages", at: issuedAt)
    XCTAssertFalse(
      AppCountdownLaunchPassStore.consume(for: "Messages", at: issuedAt.addingTimeInterval(15)))

    AppCountdownLaunchPassStore.issue(for: "Messages", at: issuedAt)
    XCTAssertTrue(
      AppCountdownLaunchPassStore.consume(for: "Messages", at: issuedAt.addingTimeInterval(14.9)))
  }

  func testPassKeyIgnoresCaseAndSurroundingWhitespace() {
    AppCountdownLaunchPassStore.issue(for: "  Messages \n", at: issuedAt)

    XCTAssertTrue(AppCountdownLaunchPassStore.consume(for: "mESSAGES", at: issuedAt))
  }

  func testPassForOneAppDoesNotSatisfyAnotherApp() {
    AppCountdownLaunchPassStore.issue(for: "Messages", at: issuedAt)

    XCTAssertFalse(AppCountdownLaunchPassStore.consume(for: "Notes", at: issuedAt))
    XCTAssertTrue(AppCountdownLaunchPassStore.consume(for: "Messages", at: issuedAt))
  }

  func testIssuePrunesExpiredPassesForOtherApps() {
    AppCountdownLaunchPassStore.issue(for: "Notes", at: issuedAt)
    AppCountdownLaunchPassStore.issue(for: "Mail", at: issuedAt.addingTimeInterval(10))
    XCTAssertEqual(
      storedPassKeys(), ["appCountdown.launchPass.mail", "appCountdown.launchPass.notes"])

    AppCountdownLaunchPassStore.issue(for: "Messages", at: issuedAt.addingTimeInterval(15))

    XCTAssertEqual(
      storedPassKeys(), ["appCountdown.launchPass.mail", "appCountdown.launchPass.messages"])
  }

  func testBlankAppNameRoundTrips() {
    AppCountdownLaunchPassStore.issue(for: "  ", at: issuedAt)

    XCTAssertEqual(storedPassKeys(), ["appCountdown.launchPass."])
    XCTAssertTrue(AppCountdownLaunchPassStore.consume(for: "", at: issuedAt))
  }

  // MARK: - Decision

  func testDecisionIsSilentWithoutSession() {
    XCTAssertFalse(
      AppCountdownDecision.shouldIntervene(
        state: FoqosControlState(session: nil),
        profile: makeProfile(enableAppCountdown: true)
      )
    )
  }

  func testDecisionIsSilentDuringBreak() {
    let onBreak = makeSession(breakStartTime: issuedAt)
    let breakEnded = makeSession(
      breakStartTime: issuedAt, breakEndTime: issuedAt.addingTimeInterval(60))

    XCTAssertFalse(shouldIntervene(session: onBreak, enableAppCountdown: true))
    XCTAssertTrue(shouldIntervene(session: breakEnded, enableAppCountdown: true))
  }

  func testDecisionIsSilentDuringPause() {
    let paused = makeSession(pauseStartTime: issuedAt)
    let pauseEnded = makeSession(
      pauseStartTime: issuedAt, pauseEndTime: issuedAt.addingTimeInterval(60))

    XCTAssertFalse(shouldIntervene(session: paused, enableAppCountdown: true))
    XCTAssertTrue(shouldIntervene(session: pauseEnded, enableAppCountdown: true))
  }

  func testDecisionIsSilentWhenProfileSnapshotIsMissing() {
    XCTAssertFalse(
      AppCountdownDecision.shouldIntervene(
        state: FoqosControlState(session: makeSession()),
        profile: nil
      )
    )
  }

  func testDecisionIsSilentWhenAppCountdownIsNotEnabled() {
    XCTAssertFalse(shouldIntervene(session: makeSession(), enableAppCountdown: nil))
    XCTAssertFalse(shouldIntervene(session: makeSession(), enableAppCountdown: false))
  }

  func testDecisionIntervenesForActiveSessionWithAppCountdownEnabled() {
    XCTAssertTrue(shouldIntervene(session: makeSession(), enableAppCountdown: true))
  }

  func testDecisionIsSilentForEndedSession() {
    let ended = makeSession(endTime: issuedAt.addingTimeInterval(3600))

    XCTAssertFalse(shouldIntervene(session: ended, enableAppCountdown: true))
  }

  // MARK: - Helpers

  private func shouldIntervene(
    session: SharedData.SessionSnapshot,
    enableAppCountdown: Bool?
  ) -> Bool {
    AppCountdownDecision.shouldIntervene(
      state: FoqosControlState(session: session),
      profile: makeProfile(enableAppCountdown: enableAppCountdown)
    )
  }

  private func makeSession(
    endTime: Date? = nil,
    breakStartTime: Date? = nil,
    breakEndTime: Date? = nil,
    pauseStartTime: Date? = nil,
    pauseEndTime: Date? = nil
  ) -> SharedData.SessionSnapshot {
    SharedData.SessionSnapshot(
      id: UUID().uuidString,
      tag: "app-countdown",
      blockedProfileId: profileId,
      startTime: issuedAt.addingTimeInterval(-600),
      endTime: endTime,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      pauseStartTime: pauseStartTime,
      pauseEndTime: pauseEndTime,
      forceStarted: false
    )
  }

  private func makeProfile(enableAppCountdown: Bool?) -> SharedData.ProfileSnapshot {
    SharedData.ProfileSnapshot(
      id: profileId,
      name: "Deep Work",
      selectedActivity: FamilyActivitySelection(),
      createdAt: issuedAt,
      updatedAt: issuedAt,
      order: 0,
      enableLiveActivity: false,
      enableBreaks: true,
      enableStrictMode: false,
      enableAllowMode: false,
      enableAllowModeDomains: false,
      enableSafariBlocking: false,
      enableAppCountdown: enableAppCountdown
    )
  }

  private func storedPassKeys() -> [String] {
    suite.dictionaryRepresentation().keys.filter { $0.hasPrefix("appCountdown.launchPass.") }
      .sorted()
  }

  private func removeStoredPasses() {
    for key in storedPassKeys() { suite.removeObject(forKey: key) }
  }
}
