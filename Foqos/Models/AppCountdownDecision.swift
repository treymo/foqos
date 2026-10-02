import Foundation

enum AppCountdownDecision {
  static func shouldIntervene(
    state: FoqosControlState,
    profile: SharedData.ProfileSnapshot?
  ) -> Bool {
    guard let session = state.session, !state.isBreakActive else { return false }
    let isPauseActive = session.pauseStartTime != nil && session.pauseEndTime == nil
    return !isPauseActive && profile?.enableAppCountdown == true
  }
}
