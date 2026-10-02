import Foundation

struct SoftUnblockStrategyData: Codable, Equatable {
  static let defaultDurationInMinutes = 15
  static let defaultMaximumUnblockCount = 3
  static let defaultAllowanceResetIntervalInHours: Int? = nil
  static let defaultEnabledAllowanceResetIntervalInHours = 6
  static let durationRange = 5...60
  static let unblockCountRange = SoftUnblockSessionState.maximumUnblockCountRange
  static let allowanceResetIntervalRangeInHours =
    SoftUnblockSessionState.allowanceResetIntervalRangeInHours
  static let waitDurationRange = 0...60

  var accessDurationInMinutes: Int
  var maximumUnblockCount: Int
  var allowanceResetIntervalInHours: Int?
  var waitDurationInSeconds: Int = 0

  static func decode(_ data: Data?) -> SoftUnblockStrategyData {
    guard let data,
      let configuration = try? JSONDecoder().decode(SoftUnblockStrategyData.self, from: data)
    else {
      return SoftUnblockStrategyData(
        accessDurationInMinutes: defaultDurationInMinutes,
        maximumUnblockCount: defaultMaximumUnblockCount,
        allowanceResetIntervalInHours: defaultAllowanceResetIntervalInHours
      )
    }

    return configuration.normalized
  }

  static func encode(_ configuration: SoftUnblockStrategyData) -> Data? {
    try? JSONEncoder().encode(configuration.normalized)
  }

  private var normalized: SoftUnblockStrategyData {
    SoftUnblockStrategyData(
      accessDurationInMinutes: min(
        max(accessDurationInMinutes, Self.durationRange.lowerBound),
        Self.durationRange.upperBound
      ),
      maximumUnblockCount: min(
        max(maximumUnblockCount, Self.unblockCountRange.lowerBound),
        Self.unblockCountRange.upperBound
      ),
      allowanceResetIntervalInHours: allowanceResetIntervalInHours.flatMap { interval in
        Self.allowanceResetIntervalRangeInHours.contains(interval) ? interval : nil
      },
      waitDurationInSeconds: min(
        max(waitDurationInSeconds, Self.waitDurationRange.lowerBound),
        Self.waitDurationRange.upperBound
      )
    )
  }
}

extension SoftUnblockStrategyData {
  // Synthesized decoding rejects JSON saved without waitDurationInSeconds.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accessDurationInMinutes = try container.decode(Int.self, forKey: .accessDurationInMinutes)
    maximumUnblockCount = try container.decode(Int.self, forKey: .maximumUnblockCount)
    allowanceResetIntervalInHours = try container.decodeIfPresent(
      Int.self,
      forKey: .allowanceResetIntervalInHours
    )
    waitDurationInSeconds =
      try container.decodeIfPresent(Int.self, forKey: .waitDurationInSeconds) ?? 0
  }
}
