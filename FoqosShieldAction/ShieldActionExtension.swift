import Foundation
import ManagedSettings
import OSLog

private let log = Logger(
  subsystem: "dev.ambitionsoftware.foqos",
  category: "SoftUnblockShieldAction"
)

class ShieldActionExtension: ShieldActionDelegate {
  override func handle(
    action: ShieldAction,
    for application: ApplicationToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    handle(
      action: action,
      resource: .application(application),
      completionHandler: completionHandler
    )
  }

  override func handle(
    action: ShieldAction,
    for webDomain: WebDomainToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    completionHandler(.close)
  }

  override func handle(
    action: ShieldAction,
    for category: ActivityCategoryToken,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    handle(
      action: action,
      resource: .category(category),
      completionHandler: completionHandler
    )
  }

  private func handle(
    action: ShieldAction,
    resource: SoftUnblockResource,
    completionHandler: @escaping (ShieldActionResponse) -> Void
  ) {
    guard action == .primaryButtonPressed,
      let session = SoftUnblockGrantStore.activeSession,
      let snapshot = SharedData.snapshot(for: session.profileId.uuidString)
    else {
      completionHandler(.close)
      return
    }

    if snapshot.enableAllowMode, case .category = resource {
      completionHandler(.close)
      return
    }

    let configuration = SoftUnblockStrategyData.decode(snapshot.strategyData)
    let durationInMinutes = max(configuration.accessDurationInMinutes, 1)
    let now = Date()
    let pendingWait = SoftUnblockGrantStore.pendingWait(
      for: resource,
      profileId: session.profileId,
      at: now
    )

    switch SoftUnblockWaitDecision.decide(
      waitDuration: configuration.waitDurationInSeconds,
      pendingWait: pendingWait,
      remainingUnblockCount: session.remainingUnblockCount,
      at: now
    ) {
    case .grant:
      break
    case .startWait:
      let waitDuration = TimeInterval(configuration.waitDurationInSeconds)
      SoftUnblockGrantStore.beginWait(
        SoftUnblockWait(
          id: UUID(),
          sessionId: session.sessionId,
          profileId: session.profileId,
          resource: resource,
          startedAt: now,
          endsAt: now.addingTimeInterval(waitDuration),
          expiresAt: now.addingTimeInterval(waitDuration + SoftUnblockWait.graceInterval)
        )
      )
      completionHandler(.defer)
      return
    case .keepWaiting:
      completionHandler(.defer)
      return
    case .close:
      completionHandler(.close)
      return
    }

    if let pendingWait {
      SoftUnblockGrantStore.removeWait(id: pendingWait.id, sessionId: pendingWait.sessionId)
    }

    let grant = SoftUnblockGrant(
      id: UUID(),
      sessionId: session.sessionId,
      profileId: session.profileId,
      resource: resource,
      createdAt: now,
      expiresAt: now.addingTimeInterval(TimeInterval(durationInMinutes * 60))
    )

    guard SoftUnblockGrantStore.issue(grant) else {
      completionHandler(.close)
      return
    }

    do {
      try SoftUnblockGrantScheduler.scheduleGrant(grant)
    } catch {
      SoftUnblockGrantStore.rollbackIssuedGrant(
        id: grant.id,
        sessionId: grant.sessionId
      )
      log.error("Failed to schedule a soft-unblock grant: \(error.localizedDescription)")
      completionHandler(.close)
      return
    }

    AppBlockerUtil().applySoftUnblockGrants(for: snapshot)
    // .defer redraws the shield, and the shield was just lifted, so the app appears.
    completionHandler(.defer)
  }
}
