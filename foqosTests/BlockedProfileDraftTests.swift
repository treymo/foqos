import XCTest

@testable import foqos

final class BlockedProfileDraftTests: ModelRegressionTestCase {
  func testSelectingTemporaryAccessDisablesAllowMode() {
    let draft = BlockedProfileDraft()
    draft.enableAllowMode = true

    draft.selectedStrategy = NFCSoftUnblockBlockingStrategy()

    XCTAssertFalse(draft.enableAllowMode)
    XCTAssertFalse(draft.selectedStrategySupportsAllowMode)
  }

  func testLoadingTemporaryAccessProfileDisablesAllowMode() {
    let profile = BlockedProfiles(
      name: "Temporary Access",
      blockingStrategyId: QRSoftUnblockBlockingStrategy.id,
      enableAllowMode: true
    )

    let draft = BlockedProfileDraft(profile: profile)

    XCTAssertFalse(draft.enableAllowMode)
    XCTAssertFalse(draft.selectedStrategySupportsAllowMode)
  }

  func testOtherStrategiesContinueToSupportAllowMode() {
    let draft = BlockedProfileDraft()

    draft.enableAllowMode = true

    XCTAssertTrue(draft.enableAllowMode)
    XCTAssertTrue(draft.selectedStrategySupportsAllowMode)
  }

  func testLoadingProfileCarriesAppCountdown() {
    let enabledProfile = BlockedProfiles(name: "Countdown", enableAppCountdown: true)
    let defaultProfile = BlockedProfiles(name: "Default")

    XCTAssertTrue(BlockedProfileDraft(profile: enabledProfile).enableAppCountdown)
    XCTAssertFalse(BlockedProfileDraft(profile: defaultProfile).enableAppCountdown)
  }

  func testSavingNewDraftWithAppCountdownCreatesProfileWithAppCountdown() throws {
    let draft = BlockedProfileDraft()
    draft.name = "Countdown"
    draft.enableAppCountdown = true

    let profile = try draft.save(existingProfile: nil, in: context)

    let fetched = try XCTUnwrap(BlockedProfiles.findProfile(byID: profile.id, in: freshContext()))
    XCTAssertTrue(fetched.enableAppCountdown)
  }

  func testSavingEditedDraftThatTurnsAppCountdownOffUpdatesProfile() throws {
    let profile = BlockedProfiles(name: "Countdown", enableAppCountdown: true)
    context.insert(profile)
    try context.save()

    let draft = BlockedProfileDraft(profile: profile)
    draft.enableAppCountdown = false
    _ = try draft.save(existingProfile: profile, in: context)

    let fetched = try XCTUnwrap(BlockedProfiles.findProfile(byID: profile.id, in: freshContext()))
    XCTAssertFalse(fetched.enableAppCountdown)
  }

  func testSavingEditedDraftThatTurnsAppCountdownOnUpdatesProfile() throws {
    let profile = BlockedProfiles(name: "Countdown")
    context.insert(profile)
    try context.save()

    let draft = BlockedProfileDraft(profile: profile)
    draft.enableAppCountdown = true
    _ = try draft.save(existingProfile: profile, in: context)

    let fetched = try XCTUnwrap(BlockedProfiles.findProfile(byID: profile.id, in: freshContext()))
    XCTAssertTrue(fetched.enableAppCountdown)
  }
}
