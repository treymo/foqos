import SwiftUI
import UIKit

enum AppCountdownChoice: Equatable {
  case continueToApp
  case stay
}

struct AppCountdownRequest: Equatable {
  let appName: String
  let profileName: String
  let countdownSeconds: Int
}

@MainActor
final class AppCountdownGate {
  typealias ShowWindow =
    @MainActor (
      _ request: AppCountdownRequest,
      _ onChoice: @escaping @MainActor (AppCountdownChoice) -> Void
    ) -> UIWindow?

  static let shared = AppCountdownGate()

  private let sceneActivationTimeout: Duration
  private let showWindow: ShowWindow
  private var presentationID: UUID?
  private var continuation: CheckedContinuation<AppCountdownChoice, Never>?
  private var window: UIWindow?
  private var waits: [Task<Void, Never>] = []

  init(
    sceneActivationTimeout: Duration = .seconds(3),
    showWindow: @escaping ShowWindow = AppCountdownGate.showWindowOnForegroundActiveScene
  ) {
    self.sceneActivationTimeout = sceneActivationTimeout
    self.showWindow = showWindow
  }

  func present(
    _ request: AppCountdownRequest,
    decisionTimeout: Duration
  ) async -> AppCountdownChoice {
    guard presentationID == nil else { return .stay }
    let id = UUID()
    presentationID = id

    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        waits = [
          Task { await self.showWindowWhenSceneIsActive(request, presentationID: id) },
          Task {
            guard (try? await Task.sleep(for: decisionTimeout)) != nil else { return }
            self.resolve(.stay, presentationID: id)
          },
        ]
      }
    } onCancel: {
      Task { @MainActor in self.resolve(.stay, presentationID: id) }
    }
  }

  private func showWindowWhenSceneIsActive(
    _ request: AppCountdownRequest,
    presentationID id: UUID
  ) async {
    let deadline = ContinuousClock.now.advanced(by: sceneActivationTimeout)
    while !Task.isCancelled {
      let shown = showWindow(request) { [weak self] choice in
        self?.resolve(choice, presentationID: id)
      }
      if let shown {
        window = shown
        return
      }
      guard ContinuousClock.now < deadline else {
        resolve(.stay, presentationID: id)
        return
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  private func resolve(_ choice: AppCountdownChoice, presentationID id: UUID) {
    guard presentationID == id, let continuation else { return }
    presentationID = nil
    self.continuation = nil
    for wait in waits { wait.cancel() }
    waits = []
    window?.isHidden = true
    window = nil
    continuation.resume(returning: choice)
  }

  private static func showWindowOnForegroundActiveScene(
    _ request: AppCountdownRequest,
    onChoice: @escaping @MainActor (AppCountdownChoice) -> Void
  ) -> UIWindow? {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
    else { return nil }

    // A window appears above any open sheet; a fullScreenCover from HomeView does not.
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.rootViewController = UIHostingController(
      rootView: AppCountdownView(request: request, onChoice: onChoice)
        .environmentObject(ThemeManager.shared)
    )
    window.makeKeyAndVisible()
    return window
  }
}
