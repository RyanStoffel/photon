import Foundation
import PhotonCore

#if canImport(AppKit)
import AppKit
#endif

public enum CalculatorProviderError: LocalizedError, Sendable {
  case unknownCommand(String)
  case invalidPayload

  public var errorDescription: String? {
    switch self {
    case let .unknownCommand(id):
      "Unknown calculator command (\(id))."
    case .invalidPayload:
      "Could not read the calculator result."
    }
  }
}

/// Inline calculator results in the default launcher list (Raycast-style).
public final class CalculatorProvider: CommandProvider, @unchecked Sendable {
  public static let idPrefix = "calculator:"

  public let id = "calculator"
  public let displayName = "Calculator"

  public init() {}

  public func commands(matching query: String) async -> [Command] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let result = CalculatorEngine.evaluate(trimmed) else {
      return []
    }
    let subtitle = Self.subtitle(for: result)
    return [
      Command(
        id: Self.commandID(for: trimmed),
        title: result.rowTitle,
        subtitle: subtitle,
        keywords: [trimmed, result.expression, result.value, "calculator", "convert"],
        providerID: id,
        icon: .symbol(name: "function")
      )
    ]
  }

  public func execute(_ command: Command) async throws {
    guard command.id.hasPrefix(Self.idPrefix) else {
      throw CalculatorProviderError.unknownCommand(command.id)
    }
    guard let query = Self.query(fromCommandID: command.id),
          let result = CalculatorEngine.evaluate(query)
    else {
      throw CalculatorProviderError.invalidPayload
    }
    try await CalculatorPasteboard.copy(result.copyValue)
  }

  static func commandID(for query: String) -> String {
    let encoded = Data(query.utf8).base64EncodedString()
    return idPrefix + encoded
  }

  static func query(fromCommandID id: String) -> String? {
    guard id.hasPrefix(idPrefix) else {
      return nil
    }
    let encoded = String(id.dropFirst(idPrefix.count))
    guard let data = Data(base64Encoded: encoded) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func subtitle(for result: CalculatorResult) -> String {
    if let words = result.wordForm {
      return "\(result.operationLabel) · \(words)"
    }
    return result.operationLabel
  }
}

enum CalculatorPasteboard {
  static func copy(_ text: String) async throws {
    #if canImport(AppKit)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      throw CalculatorProviderError.invalidPayload
    }
    #else
    _ = text
    #endif
  }
}
