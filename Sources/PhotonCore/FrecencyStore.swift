import Foundation

/// Combines frequency and recency into a single ranking score.
///
/// `score = log2(1 + uses) * 0.5^(days / halfLifeDays)`.
/// Unused ids score `0`. The store is a value type; persist it with `save(to:)`.
public struct FrecencyStore: Codable, Sendable, Equatable {
  public var halfLifeDays: Double
  public private(set) var records: [String: FrecencyRecord]

  public init(halfLifeDays: Double = 7, records: [String: FrecencyRecord] = [:]) {
    self.halfLifeDays = halfLifeDays
    self.records = records
  }

  public mutating func recordUse(id: String, at date: Date = Date()) {
    if var existing = records[id] {
      existing.count += 1
      existing.lastUsed = date
      records[id] = existing
    } else {
      records[id] = FrecencyRecord(count: 1, lastUsed: date)
    }
  }

  public func score(id: String, now: Date = Date()) -> Double {
    guard let record = records[id] else {
      return 0
    }
    return Self.score(record: record, now: now, halfLifeDays: halfLifeDays)
  }

  public static func score(record: FrecencyRecord, now: Date, halfLifeDays: Double) -> Double {
    let days = max(0, now.timeIntervalSince(record.lastUsed) / 86400)
    let recency = pow(0.5, days / max(halfLifeDays, 0.001))
    return log2(1 + Double(record.count)) * recency
  }

  public func save(to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(self)
    try data.write(to: url, options: .atomic)
  }

  public static func load(from url: URL, defaultHalfLifeDays: Double = 7) -> FrecencyStore {
    guard let data = try? Data(contentsOf: url),
          let store = try? JSONDecoder().decode(FrecencyStore.self, from: data)
    else {
      return FrecencyStore(halfLifeDays: defaultHalfLifeDays)
    }
    return store
  }
}

public struct FrecencyRecord: Codable, Sendable, Equatable {
  public var count: Int
  public var lastUsed: Date

  public init(count: Int, lastUsed: Date) {
    self.count = count
    self.lastUsed = lastUsed
  }
}
