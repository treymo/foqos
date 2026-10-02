import SwiftUI

struct AppCountdownSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager

  private let steps = [
    "Open Shortcuts, go to the Automation tab, and tap +.",
    "Choose App, pick the app (for example Messages), keep Is Opened checked, uncheck Is Closed, choose Run Immediately, and turn off Notify When Run. Tap Next.",
    "Tap New Blank Automation, search Foqos, and add Countdown Before App. Type the app's name in App Name.",
    "Add an If action. Set it to: If Countdown Before App is Yes.",
    "Inside the If, add Open App and pick the same app. Leave Otherwise empty and tap Done.",
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Text(
              "Foqos can't put a shield on an app without blocking it. Instead, a Shortcuts automation asks Foqos to show a countdown each time the app opens. Build one automation per app."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
              ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                  Text("\(index + 1)")
                    .font(.headline)
                    .foregroundStyle(themeManager.themeColor)

                  Text(step)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }

            Text(
              "Only add automations for apps this profile leaves open. Apps this profile blocks get the shield, and Temporary Access profiles can add a wait there instead. When no profile with the countdown turned on is active, the automation runs silently and the app opens as usual."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          .padding(24)
        }

        ActionButton(
          title: "Open Shortcuts",
          backgroundColor: themeManager.themeColor
        ) {
          if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
      }
      .navigationTitle("Set Up in Shortcuts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
        }
      }
    }
  }
}

#Preview {
  AppCountdownSetupView()
    .environmentObject(ThemeManager.shared)
}
