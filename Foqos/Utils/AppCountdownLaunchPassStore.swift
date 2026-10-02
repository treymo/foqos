import Foundation

enum AppCountdownLaunchPassStore {
  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  private static let keyPrefix = "appCountdown.launchPass."
  private static let lifetime: TimeInterval = 15

  static func issue(for appName: String, at date: Date) {
    removeExpiredPasses(at: date)
    suite.set(date.addingTimeInterval(lifetime), forKey: key(for: appName))
  }

  static func consume(for appName: String, at date: Date) -> Bool {
    let key = key(for: appName)
    guard let expiresAt = suite.object(forKey: key) as? Date else { return false }
    suite.removeObject(forKey: key)
    return date < expiresAt
  }

  private static func removeExpiredPasses(at date: Date) {
    for (key, value) in suite.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
      if let expiresAt = value as? Date, date < expiresAt { continue }
      suite.removeObject(forKey: key)
    }
  }

  private static func key(for appName: String) -> String {
    keyPrefix + appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
