import SwiftUI

struct AppCountdownView: View {
  @EnvironmentObject var themeManager: ThemeManager

  let request: AppCountdownRequest
  let onChoice: @MainActor (AppCountdownChoice) -> Void

  @State private var secondsLeft: Int

  init(
    request: AppCountdownRequest,
    onChoice: @escaping @MainActor (AppCountdownChoice) -> Void
  ) {
    self.request = request
    self.onChoice = onChoice
    _secondsLeft = State(initialValue: request.countdownSeconds)
  }

  private var continueTitle: String {
    secondsLeft > 0 ? "Continue in \(secondsLeft)s" : "Continue to \(request.appName)"
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      Text("\(request.profileName) is active")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Text("Do you need \(request.appName) right now?")
        .font(.title2.bold())
        .multilineTextAlignment(.center)

      Text("\(secondsLeft)")
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .contentTransition(.numericText())

      Text("Take a breath. Your \(request.profileName) session is still running.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Spacer()

      ActionButton(title: "Don't open", backgroundColor: themeManager.themeColor) {
        onChoice(.stay)
      }

      Button {
        onChoice(.continueToApp)
      } label: {
        Text(continueTitle)
          .font(.headline)
      }
      .tint(themeManager.themeColor)
      .disabled(secondsLeft > 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemBackground))
    .task {
      while secondsLeft > 0 {
        guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
        withAnimation { secondsLeft -= 1 }
      }
    }
  }
}

#Preview {
  AppCountdownView(
    request: AppCountdownRequest(
      appName: "Messages",
      profileName: "Deep Work",
      countdownSeconds: 10
    )
  ) { _ in }
  .environmentObject(ThemeManager.shared)
}
