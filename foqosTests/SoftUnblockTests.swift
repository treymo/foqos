import DeviceActivity
import XCTest

@testable import foqos

final class SoftUnblockTests: XCTestCase {
  private let suite = UserDefaults(suiteName: "group.dev.ambitionsoftware.foqos")!

  func testStrategyConfigurationRoundTrips() {
    let configuration = SoftUnblockStrategyData(
      accessDurationInMinutes: 30,
      maximumUnblockCount: 6,
      allowanceResetIntervalInHours: 12
    )
    let encoded = SoftUnblockStrategyData.encode(configuration)

    XCTAssertEqual(SoftUnblockStrategyData.decode(encoded), configuration)
  }

  func testStrategyConfigurationFallsBackForMissingData() {
    let configuration = SoftUnblockStrategyData.decode(nil)

    XCTAssertEqual(
      configuration.accessDurationInMinutes,
      SoftUnblockStrategyData.defaultDurationInMinutes
    )
    XCTAssertEqual(
      configuration.maximumUnblockCount,
      SoftUnblockStrategyData.defaultMaximumUnblockCount
    )
    XCTAssertNil(configuration.allowanceResetIntervalInHours)
    XCTAssertEqual(configuration.waitDurationInSeconds, 0)
  }

  func testLifecycleRegistryBeginsSessionWithDefaultConfiguration() {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let profileId = UUID()
    let sessionId = UUID().uuidString
    let startedAt = Date(timeIntervalSince1970: 1_000_000)
    let context = BlockingSessionLifecycleContext(
      strategyId: SoftUnblockSessionLifecycleHandler.nfcStrategyId,
      strategyData: nil,
      sessionId: sessionId,
      profileId: profileId,
      startedAt: startedAt
    )
    BlockingSessionLifecycleRegistry.sessionDidStart(context)

    let session = SoftUnblockGrantStore.currentSession(at: startedAt)
    XCTAssertEqual(session?.sessionId, sessionId)
    XCTAssertEqual(session?.profileId, profileId)
    XCTAssertEqual(
      session?.maximumUnblockCount,
      SoftUnblockStrategyData.defaultMaximumUnblockCount
    )
    XCTAssertEqual(session?.allowanceWindowStartedAt, startedAt)
    XCTAssertNil(session?.allowanceResetIntervalInHours)
  }

  func testLifecycleRegistryBeginsSessionWithSavedConfiguration() {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let configuration = SoftUnblockStrategyData(
      accessDurationInMinutes: 30,
      maximumUnblockCount: 6,
      allowanceResetIntervalInHours: 12
    )
    let startedAt = Date(timeIntervalSince1970: 1_000_000)

    BlockingSessionLifecycleRegistry.sessionDidStart(
      BlockingSessionLifecycleContext(
        strategyId: SoftUnblockSessionLifecycleHandler.qrStrategyId,
        strategyData: SoftUnblockStrategyData.encode(configuration),
        sessionId: UUID().uuidString,
        profileId: UUID(),
        startedAt: startedAt
      )
    )

    let session = SoftUnblockGrantStore.currentSession(at: startedAt)
    XCTAssertEqual(session?.maximumUnblockCount, configuration.maximumUnblockCount)
    XCTAssertEqual(
      session?.allowanceResetIntervalInHours,
      configuration.allowanceResetIntervalInHours
    )
    XCTAssertEqual(
      session?.nextAllowanceResetAt,
      startedAt.addingTimeInterval(12 * 60 * 60)
    )
  }

  func testLifecycleRegistryClearsTemporaryAccessStateForAnotherStrategy() {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    BlockingSessionLifecycleRegistry.sessionDidStart(
      BlockingSessionLifecycleContext(
        strategyId: SoftUnblockSessionLifecycleHandler.nfcStrategyId,
        strategyData: nil,
        sessionId: UUID().uuidString,
        profileId: UUID(),
        startedAt: Date()
      )
    )
    XCTAssertNotNil(SoftUnblockGrantStore.activeSession)

    BlockingSessionLifecycleRegistry.sessionDidStart(
      BlockingSessionLifecycleContext(
        strategyId: ManualBlockingStrategy.id,
        strategyData: nil,
        sessionId: UUID().uuidString,
        profileId: UUID(),
        startedAt: Date()
      )
    )

    XCTAssertNil(SoftUnblockGrantStore.activeSession)
  }

  func testTemporaryAccessLifecycleHandlerEndsMatchingSession() {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let sessionId = UUID().uuidString
    var stoppedSessionId: String?
    let context = BlockingSessionLifecycleContext(
      strategyId: SoftUnblockSessionLifecycleHandler.nfcStrategyId,
      strategyData: nil,
      sessionId: sessionId,
      profileId: UUID(),
      startedAt: Date()
    )
    let handler = SoftUnblockSessionLifecycleHandler(
      stopAllScheduledGrants: {},
      stopScheduledGrantsForSession: { stoppedSessionId = $0 }
    )
    handler.sessionDidStart(context)

    handler.sessionDidEnd(context)

    XCTAssertEqual(stoppedSessionId, sessionId)
    XCTAssertNil(SoftUnblockGrantStore.activeSession)
  }

  func testAllowanceDoesNotResetBeforeBoundary() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var session = makeSession(startedAt: start, resetHours: 6, usedUnblocks: 2)

    XCTAssertFalse(
      session.resetAllowanceIfNeeded(at: start.addingTimeInterval((6 * 60 * 60) - 1))
    )
    XCTAssertEqual(session.usedUnblockCount, 2)
  }

  func testAllowanceResetsAtBoundary() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var session = makeSession(startedAt: start, resetHours: 6, usedUnblocks: 2)
    let boundary = start.addingTimeInterval(6 * 60 * 60)

    XCTAssertTrue(session.resetAllowanceIfNeeded(at: boundary))
    XCTAssertEqual(session.usedUnblockCount, 0)
    XCTAssertEqual(session.allowanceWindowStartedAt, boundary)
    XCTAssertEqual(session.nextAllowanceResetAt, boundary.addingTimeInterval(6 * 60 * 60))
  }

  func testAllowanceAdvancesAcrossMissedWindows() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var session = makeSession(startedAt: start, resetHours: 6, usedUnblocks: 2)
    let currentDate = start.addingTimeInterval((19 * 60 * 60) + 10)

    XCTAssertTrue(session.resetAllowanceIfNeeded(at: currentDate))
    XCTAssertEqual(session.usedUnblockCount, 0)
    XCTAssertEqual(
      session.allowanceWindowStartedAt,
      start.addingTimeInterval(18 * 60 * 60)
    )
    XCTAssertEqual(
      session.nextAllowanceResetAt,
      start.addingTimeInterval(24 * 60 * 60)
    )
  }

  func testNeverResetPreservesUsage() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var session = makeSession(startedAt: start, resetHours: nil, usedUnblocks: 2)

    XCTAssertFalse(
      session.resetAllowanceIfNeeded(at: start.addingTimeInterval(48 * 60 * 60))
    )
    XCTAssertEqual(session.usedUnblockCount, 2)
  }

  func testRollbackOnlyMatchesCurrentAllowanceWindow() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var session = makeSession(startedAt: start, resetHours: 6, usedUnblocks: 2)
    let resetBoundary = start.addingTimeInterval(6 * 60 * 60)
    session.resetAllowanceIfNeeded(at: resetBoundary)

    XCTAssertFalse(
      session.containsAllowanceUse(createdAt: resetBoundary.addingTimeInterval(-1))
    )
    XCTAssertTrue(
      session.containsAllowanceUse(createdAt: resetBoundary.addingTimeInterval(1))
    )
  }

  func testActivityIdentifiersParseWithoutEmbeddingResourceTokens() {
    let profileId = UUID()
    let sessionId = UUID().uuidString
    let grantId = UUID()
    let activityName = DeviceActivityName(
      rawValue:
        "\(SoftUnblockGrantScheduler.activityId):\(profileId.uuidString)|\(sessionId)|\(grantId.uuidString)"
    )

    XCTAssertEqual(
      SoftUnblockGrantScheduler.identifiers(from: activityName),
      SoftUnblockGrantScheduler.ActivityIdentifiers(
        profileId: profileId,
        sessionId: sessionId,
        grantId: grantId
      )
    )
  }

  func testActivityIdentifiersRejectMalformedNames() {
    let activityName = DeviceActivityName(
      rawValue: "\(SoftUnblockGrantScheduler.activityId):invalid"
    )

    XCTAssertNil(SoftUnblockGrantScheduler.identifiers(from: activityName))
  }

  func testStrategyConfigurationDecodesDataWithoutWaitDuration() {
    let data = Data(
      #"{"accessDurationInMinutes":30,"maximumUnblockCount":6,"allowanceResetIntervalInHours":12}"#
        .utf8
    )

    let configuration = SoftUnblockStrategyData.decode(data)

    XCTAssertEqual(configuration.accessDurationInMinutes, 30)
    XCTAssertEqual(configuration.maximumUnblockCount, 6)
    XCTAssertEqual(configuration.allowanceResetIntervalInHours, 12)
    XCTAssertEqual(configuration.waitDurationInSeconds, 0)
  }

  func testStrategyConfigurationRoundTripsWaitDuration() {
    let configuration = SoftUnblockStrategyData(
      accessDurationInMinutes: 30,
      maximumUnblockCount: 6,
      allowanceResetIntervalInHours: 12,
      waitDurationInSeconds: 45
    )
    let encoded = SoftUnblockStrategyData.encode(configuration)

    XCTAssertEqual(SoftUnblockStrategyData.decode(encoded), configuration)
  }

  func testStrategyConfigurationClampsWaitDuration() {
    XCTAssertEqual(decodedWaitDuration(-5), 0)
    XCTAssertEqual(decodedWaitDuration(999), 60)
  }

  func testWaitIsWaitingUntilEndsAt() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertTrue(wait.isWaiting(at: start))
    XCTAssertTrue(wait.isWaiting(at: start.addingTimeInterval(29.9)))
    XCTAssertFalse(wait.isWaiting(at: start.addingTimeInterval(30)))
  }

  func testWaitExpiresAfterGraceInterval() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)
    let expiry = start.addingTimeInterval(30 + SoftUnblockWait.graceInterval)

    XCTAssertFalse(wait.isExpired(at: start.addingTimeInterval(30)))
    XCTAssertFalse(wait.isExpired(at: expiry.addingTimeInterval(-1)))
    XCTAssertTrue(wait.isExpired(at: expiry))
  }

  func testWaitIsExpiredWhenClockIsBeforeStart() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertTrue(wait.isExpired(at: start.addingTimeInterval(-1)))
  }

  func testWaitRemainingSecondsRoundsUp() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(wait.remainingSeconds(at: start), 30)
    XCTAssertEqual(wait.remainingSeconds(at: start.addingTimeInterval(0.5)), 30)
    XCTAssertEqual(wait.remainingSeconds(at: start.addingTimeInterval(29.1)), 1)
    XCTAssertEqual(wait.remainingSeconds(at: start.addingTimeInterval(30)), 1)
  }

  func testClearAllRemovesWaits() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let wait = try beginSessionAndWait()
    XCTAssertEqual(storedWaitKeys().count, 1)

    SoftUnblockGrantStore.clearAll()

    XCTAssertEqual(storedWaitKeys(), [])
    XCTAssertNil(
      SoftUnblockGrantStore.pendingWait(
        for: wait.resource,
        profileId: wait.profileId,
        at: wait.startedAt
      )
    )
  }

  func testEndSessionRemovesWaits() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let wait = try beginSessionAndWait()
    XCTAssertEqual(storedWaitKeys().count, 1)

    SoftUnblockGrantStore.endSession(sessionId: wait.sessionId)

    XCTAssertEqual(storedWaitKeys(), [])
  }

  func testPendingWaitIsNilWithoutSession() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let wait = try beginSessionAndWait()
    XCTAssertEqual(
      SoftUnblockGrantStore.pendingWait(
        for: wait.resource,
        profileId: wait.profileId,
        at: wait.startedAt
      ),
      wait
    )

    suite.removeObject(forKey: "softUnblock.activeSession")

    XCTAssertNil(
      SoftUnblockGrantStore.pendingWait(
        for: wait.resource,
        profileId: wait.profileId,
        at: wait.startedAt
      )
    )
  }

  func testUndecodableWaitRecordCountsAsNoWait() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)
    beginSession(for: wait)
    suite.set(
      Data("not a wait".utf8),
      forKey: "softUnblock.wait.\(wait.sessionId).\(UUID().uuidString)"
    )

    XCTAssertNil(
      SoftUnblockGrantStore.pendingWait(for: wait.resource, profileId: wait.profileId, at: start)
    )
    XCTAssertEqual(SoftUnblockGrantStore.beginWait(wait), wait)
    XCTAssertEqual(
      SoftUnblockGrantStore.pendingWait(for: wait.resource, profileId: wait.profileId, at: start),
      wait
    )
  }

  func testBeginWaitTwiceReturnsSameWait() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let first = try beginSessionAndWait()
    let second = try makeWait(
      sessionId: first.sessionId,
      profileId: first.profileId,
      startedAt: first.startedAt.addingTimeInterval(5),
      durationInSeconds: 30
    )
    let otherResource = try makeWait(
      sessionId: first.sessionId,
      profileId: first.profileId,
      resource: makeResource(2),
      startedAt: first.startedAt.addingTimeInterval(5),
      durationInSeconds: 30
    )

    XCTAssertEqual(SoftUnblockGrantStore.beginWait(second), first)
    XCTAssertEqual(SoftUnblockGrantStore.beginWait(otherResource), otherResource)
    XCTAssertEqual(storedWaitKeys().count, 2)
  }

  func testBeginWaitReplacesExpiredWaitForSameResource() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let expired = try beginSessionAndWait()
    let restartedAt = expired.expiresAt.addingTimeInterval(60)
    let replacement = try makeWait(
      sessionId: expired.sessionId,
      profileId: expired.profileId,
      startedAt: restartedAt,
      durationInSeconds: 30
    )

    XCTAssertEqual(SoftUnblockGrantStore.beginWait(replacement), replacement)
    XCTAssertEqual(
      storedWaitKeys(),
      ["softUnblock.wait.\(replacement.sessionId).\(replacement.id.uuidString)"]
    )
  }

  func testBeginWaitIgnoresAnotherProfile() throws {
    SoftUnblockGrantStore.clearAll()
    defer { SoftUnblockGrantStore.clearAll() }

    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)
    beginSession(for: wait)
    let otherProfileWait = try makeWait(
      sessionId: wait.sessionId,
      startedAt: start,
      durationInSeconds: 30
    )

    SoftUnblockGrantStore.beginWait(otherProfileWait)

    XCTAssertEqual(storedWaitKeys(), [])
  }

  func testWaitDecisionGrantsWhenWaitIsOff() {
    XCTAssertEqual(
      SoftUnblockWaitDecision.decide(
        waitDuration: 0,
        pendingWait: nil,
        remainingUnblockCount: 2,
        at: Date(timeIntervalSince1970: 1_000_000)
      ),
      .grant
    )
  }

  func testWaitDecisionStartsWaitOnFirstTap() {
    XCTAssertEqual(
      SoftUnblockWaitDecision.decide(
        waitDuration: 30,
        pendingWait: nil,
        remainingUnblockCount: 2,
        at: Date(timeIntervalSince1970: 1_000_000)
      ),
      .startWait
    )
  }

  func testWaitDecisionKeepsWaitingUntilEndsAt() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(decide(wait, at: start.addingTimeInterval(10)), .keepWaiting)
  }

  func testWaitDecisionGrantsBetweenEndsAtAndExpiry() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(decide(wait, at: wait.endsAt), .grant)
    XCTAssertEqual(decide(wait, at: wait.expiresAt.addingTimeInterval(-1)), .grant)
  }

  func testWaitDecisionStartsNewWaitAfterExpiry() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(decide(wait, at: wait.expiresAt), .startWait)
    XCTAssertEqual(decide(wait, at: start.addingTimeInterval(-1)), .startWait)
  }

  func testWaitDecisionClosesWithoutRemainingOpens() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(
      SoftUnblockWaitDecision.decide(
        waitDuration: 30,
        pendingWait: nil,
        remainingUnblockCount: 0,
        at: start
      ),
      .close
    )
    XCTAssertEqual(decide(wait, at: wait.endsAt, remainingUnblockCount: 0), .close)
  }

  func testWaitDecisionKeepsExistingWaitEndAfterConfigurationChange() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let wait = try makeWait(startedAt: start, durationInSeconds: 30)

    XCTAssertEqual(
      decide(wait, at: start.addingTimeInterval(10), waitDuration: 5),
      .keepWaiting
    )
    XCTAssertEqual(decide(wait, at: wait.endsAt, waitDuration: 60), .grant)
  }

  func testResourcesDecodedFromJSONLiteralsCompareByToken() throws {
    XCTAssertNotNil(try makeResource(1).applicationToken)
    XCTAssertEqual(try makeResource(1), try makeResource(1))
    XCTAssertNotEqual(try makeResource(1), try makeResource(2))
  }

  private func makeResource(_ seed: UInt8) throws -> SoftUnblockResource {
    let tokenData = Data(repeating: seed, count: 128).base64EncodedString()
    let literal = #"{"application":{"_0":{"data":"\#(tokenData)"}}}"#
    return try JSONDecoder().decode(SoftUnblockResource.self, from: Data(literal.utf8))
  }

  private func makeWait(
    sessionId: String = UUID().uuidString,
    profileId: UUID = UUID(),
    resource: SoftUnblockResource? = nil,
    startedAt: Date,
    durationInSeconds: TimeInterval
  ) throws -> SoftUnblockWait {
    let endsAt = startedAt.addingTimeInterval(durationInSeconds)
    return SoftUnblockWait(
      id: UUID(),
      sessionId: sessionId,
      profileId: profileId,
      resource: try resource ?? makeResource(1),
      startedAt: startedAt,
      endsAt: endsAt,
      expiresAt: endsAt.addingTimeInterval(SoftUnblockWait.graceInterval)
    )
  }

  private func beginSession(for wait: SoftUnblockWait) {
    SoftUnblockGrantStore.beginSession(
      sessionId: wait.sessionId,
      profileId: wait.profileId,
      maximumUnblockCount: 3,
      allowanceResetIntervalInHours: nil,
      startedAt: wait.startedAt
    )
  }

  private func beginSessionAndWait() throws -> SoftUnblockWait {
    let wait = try makeWait(
      startedAt: Date(timeIntervalSince1970: 1_000_000),
      durationInSeconds: 30
    )
    beginSession(for: wait)
    return SoftUnblockGrantStore.beginWait(wait)
  }

  private func storedWaitKeys() -> [String] {
    suite.dictionaryRepresentation().keys.filter { $0.hasPrefix("softUnblock.wait.") }.sorted()
  }

  private func decodedWaitDuration(_ waitDurationInSeconds: Int) -> Int {
    let configuration = SoftUnblockStrategyData(
      accessDurationInMinutes: 15,
      maximumUnblockCount: 3,
      allowanceResetIntervalInHours: nil,
      waitDurationInSeconds: waitDurationInSeconds
    )
    return SoftUnblockStrategyData.decode(SoftUnblockStrategyData.encode(configuration))
      .waitDurationInSeconds
  }

  private func decide(
    _ wait: SoftUnblockWait,
    at date: Date,
    waitDuration: Int = 30,
    remainingUnblockCount: Int = 2
  ) -> SoftUnblockWaitDecision {
    SoftUnblockWaitDecision.decide(
      waitDuration: waitDuration,
      pendingWait: wait,
      remainingUnblockCount: remainingUnblockCount,
      at: date
    )
  }

  private func makeSession(
    startedAt: Date,
    resetHours: Int?,
    usedUnblocks: Int
  ) -> SoftUnblockSessionState {
    SoftUnblockSessionState(
      sessionId: UUID().uuidString,
      profileId: UUID(),
      maximumUnblockCount: 3,
      allowanceResetIntervalInHours: resetHours,
      allowanceWindowStartedAt: startedAt,
      nextAllowanceResetAt: resetHours.map {
        startedAt.addingTimeInterval(TimeInterval($0 * 60 * 60))
      },
      usedUnblockCount: usedUnblocks
    )
  }
}
