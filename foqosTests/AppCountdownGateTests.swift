import UIKit
import XCTest

@testable import foqos

@MainActor
final class AppCountdownGateTests: XCTestCase {
  private let request = AppCountdownRequest(
    appName: "Messages",
    profileName: "Deep Work",
    countdownSeconds: 10
  )
  private var isSceneActive = true
  private var showCount = 0
  private var window: UIWindow?
  private var choose: (@MainActor (AppCountdownChoice) -> Void)?
  private var windowShown: XCTestExpectation?

  func testChoosingReturnsTheChoiceAndHidesTheWindow() async throws {
    for choice in [AppCountdownChoice.continueToApp, .stay] {
      let presentation = await startPresenting(on: makeGate())
      try XCTUnwrap(choose)(choice)
      let result = await presentation.value

      XCTAssertEqual(result, choice)
      XCTAssertEqual(window?.isHidden, true)
    }
  }

  func testSecondConcurrentPresentStaysAtOnceAndFirstKeepsTheUserChoice() async throws {
    let gate = makeGate()
    let first = await startPresenting(on: gate)
    let clock = ContinuousClock()
    let secondStartedAt = clock.now
    let second = await gate.present(request, decisionTimeout: .seconds(30))

    XCTAssertEqual(second, .stay)
    XCTAssertLessThan(clock.now - secondStartedAt, .seconds(1))
    XCTAssertEqual(showCount, 1)

    try XCTUnwrap(choose)(.continueToApp)
    let firstResult = await first.value

    XCTAssertEqual(firstResult, .continueToApp)
  }

  func testCancellingThePresentingTaskStays() async {
    let presentation = await startPresenting(on: makeGate())
    presentation.cancel()
    let result = await presentation.value

    XCTAssertEqual(result, .stay)
    XCTAssertEqual(window?.isHidden, true)
  }

  func testNoForegroundActiveSceneWithinTheSceneTimeoutStays() async {
    isSceneActive = false
    let gate = makeGate(sceneActivationTimeout: .milliseconds(300))
    let clock = ContinuousClock()
    let startedAt = clock.now
    let result = await gate.present(request, decisionTimeout: .seconds(30))
    let elapsed = clock.now - startedAt

    XCTAssertEqual(result, .stay)
    XCTAssertGreaterThan(showCount, 1)
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(300))
    XCTAssertLessThan(elapsed, .seconds(5))
  }

  func testNoChoiceWithinTheDecisionTimeoutStays() async {
    let presentation = await startPresenting(
      on: makeGate(),
      decisionTimeout: .milliseconds(300)
    )
    let result = await presentation.value

    XCTAssertEqual(result, .stay)
    XCTAssertEqual(window?.isHidden, true)
  }

  func testGateAcceptsANewPresentAfterEachKindOfResolution() async throws {
    let gate = makeGate(sceneActivationTimeout: .milliseconds(300))

    let chosen = await startPresenting(on: gate)
    try XCTUnwrap(choose)(.stay)
    _ = await chosen.value
    try await assertPresentReturnsTheUserChoice(on: gate)

    let cancelled = await startPresenting(on: gate)
    cancelled.cancel()
    _ = await cancelled.value
    try await assertPresentReturnsTheUserChoice(on: gate)

    let timedOut = await startPresenting(on: gate, decisionTimeout: .milliseconds(300))
    _ = await timedOut.value
    try await assertPresentReturnsTheUserChoice(on: gate)

    isSceneActive = false
    _ = await gate.present(request, decisionTimeout: .seconds(30))
    isSceneActive = true
    try await assertPresentReturnsTheUserChoice(on: gate)
  }

  private func makeGate(sceneActivationTimeout: Duration = .seconds(2)) -> AppCountdownGate {
    AppCountdownGate(sceneActivationTimeout: sceneActivationTimeout) { [unowned self] _, onChoice in
      showCount += 1
      guard isSceneActive else { return nil }
      let window = UIWindow(frame: .zero)
      window.isHidden = false
      self.window = window
      choose = onChoice
      windowShown?.fulfill()
      windowShown = nil
      return window
    }
  }

  private func startPresenting(
    on gate: AppCountdownGate,
    decisionTimeout: Duration = .seconds(30)
  ) async -> Task<AppCountdownChoice, Never> {
    choose = nil
    window = nil
    let shown = expectation(description: "Countdown window shown")
    windowShown = shown
    let presentation = Task { await gate.present(request, decisionTimeout: decisionTimeout) }
    await fulfillment(of: [shown], timeout: 2)
    return presentation
  }

  private func assertPresentReturnsTheUserChoice(
    on gate: AppCountdownGate,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let presentation = await startPresenting(on: gate)
    try XCTUnwrap(choose, file: file, line: line)(.continueToApp)
    let result = await presentation.value

    XCTAssertEqual(result, .continueToApp, file: file, line: line)
  }
}
