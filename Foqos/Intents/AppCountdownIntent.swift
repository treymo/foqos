import AppIntents
import Foundation

@available(iOS 26.0, *)
struct AppCountdownIntent: AppIntent {
  static var title: LocalizedStringResource = "Countdown Before App"
  static var description = IntentDescription(
    "Run from a 'When app is opened' automation. Shows a Foqos countdown when the active profile has Countdown for Other Apps enabled. Returns true when Foqos interrupted the launch and the app should be re-opened."
  )
  static var supportedModes: IntentModes = [.background, .foreground(.dynamic)]

  @Parameter(title: "App Name")
  var appName: String

  // Silent paths return false because an extra Open App would run the automation again.
  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    if AppCountdownLaunchPassStore.consume(for: appName, at: Date()) {
      return .result(value: false)
    }

    let state = FoqosControlState(session: SharedData.getActiveSharedSession())
    let profile = state.session.flatMap {
      SharedData.snapshot(for: $0.blockedProfileId.uuidString)
    }
    guard AppCountdownDecision.shouldIntervene(state: state, profile: profile),
      let profile,
      systemContext.currentMode.canContinueInForeground
    else {
      return .result(value: false)
    }

    try await continueInForeground(alwaysConfirm: false)

    let choice = await AppCountdownGate.shared.present(
      AppCountdownRequest(
        appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
        profileName: profile.name,
        countdownSeconds: 10
      ),
      decisionTimeout: .seconds(25)
    )
    guard choice == .continueToApp else { return .result(value: false) }

    AppCountdownLaunchPassStore.issue(for: appName, at: Date())
    return .result(value: true)
  }
}
