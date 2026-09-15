import Foundation

enum MathExpression {
  static func evaluate(_ input: String) -> CalculatorResult? {
    let tokens = tokenize(input)
    guard !tokens.isEmpty, containsOperator(tokens) else {
      return nil
    }
    var parser = Parser(tokens: tokens)
    guard let value = parser.parseExpression(), parser.isAtEnd else {
      return nil
    }
    guard value.isFinite else {
      return nil
    }
    let formatted = formatCalculatorNumber(value)
    let label = parser.lastOperationLabel ?? "Calculate"
    let words = NumberWords.spokenForm(for: value)
    return CalculatorResult(
      expression: compact(input),
      value: formatted,
      operationLabel: label,
      wordForm: words
    )
  }

  private static func compact(_ input: String) -> String {
    input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func containsOperator(_ tokens: [Token]) -> Bool {
    for token in tokens {
      if case .op = token {
        return true
      }
    }
    return false
  }

  private enum Token: Equatable {
    case number(Double)
    case op(Character)
    case lparen
    case rparen
  }

  private static func tokenize(_ input: String) -> [Token] {
    var tokens: [Token] = []
    var index = input.startIndex
    var pendingUnary = true

    while index < input.endIndex {
      let char = input[index]
      if char.isWhitespace {
        index = input.index(after: index)
        continue
      }
      if char.isNumber || char == "." {
        guard let (value, next) = readNumber(in: input, from: index) else {
          return []
        }
        tokens.append(.number(value))
        pendingUnary = false
        index = next
        continue
      }
      if char == "(" {
        tokens.append(.lparen)
        pendingUnary = true
        index = input.index(after: index)
        continue
      }
      if char == ")" {
        tokens.append(.rparen)
        pendingUnary = false
        index = input.index(after: index)
        continue
      }
      if "+-*/^%".contains(char) {
        if char == "-", pendingUnary {
          tokens.append(.number(0))
        }
        tokens.append(.op(char))
        pendingUnary = true
        index = input.index(after: index)
        continue
      }
      return []
    }
    return tokens
  }

  private static func readNumber(in input: String, from start: String.Index) -> (Double, String.Index)? {
    var index = start
    var sawDot = input[index] == "."
    index = input.index(after: index)
    while index < input.endIndex {
      let next = input[index]
      if next.isNumber {
        index = input.index(after: index)
      } else if next == ".", !sawDot {
        sawDot = true
        index = input.index(after: index)
      } else {
        break
      }
    }
    guard let value = Double(input[start ..< index]) else {
      return nil
    }
    return (value, index)
  }

  private struct Parser {
    let tokens: [Token]
    var position = 0
    private(set) var lastOperationLabel: String?

    init(tokens: [Token]) {
      self.tokens = tokens
    }

    var isAtEnd: Bool {
      position >= tokens.count
    }

    mutating func parseExpression() -> Double? {
      parseAddition()
    }

    private mutating func parseAddition() -> Double? {
      guard var value = parseMultiplication() else {
        return nil
      }
      while match(.op("+")) || match(.op("-")) {
        let add = previousOp == "+"
        lastOperationLabel = add ? "Add" : "Subtract"
        guard let rhs = parseMultiplication() else {
          return nil
        }
        value = add ? value + rhs : value - rhs
      }
      return value
    }

    private mutating func parseMultiplication() -> Double? {
      guard var value = parsePower() else {
        return nil
      }
      while match(.op("*")) || match(.op("/")) || match(.op("%")) {
        let op = previousOp!
        lastOperationLabel = op == "*" ? "Multiply" : op == "/" ? "Divide" : "Modulo"
        guard let rhs = parsePower() else {
          return nil
        }
        switch op {
        case "*": value *= rhs
        case "/":
          guard rhs != 0 else {
            return nil
          }
          value /= rhs
        case "%":
          guard rhs != 0 else {
            return nil
          }
          value = value.truncatingRemainder(dividingBy: rhs)
        default: break
        }
      }
      return value
    }

    private mutating func parsePower() -> Double? {
      guard var value = parseUnary() else {
        return nil
      }
      if match(.op("^")) {
        lastOperationLabel = "Power"
        guard let rhs = parseUnary() else {
          return nil
        }
        value = pow(value, rhs)
      }
      return value
    }

    private mutating func parseUnary() -> Double? {
      if match(.op("-")) {
        guard let value = parseUnary() else {
          return nil
        }
        return -value
      }
      if match(.op("+")) {
        return parseUnary()
      }
      return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
      if let value = consumeNumber() {
        return value
      }
      if match(.lparen) {
        guard let value = parseExpression(), match(.rparen) else {
          return nil
        }
        return value
      }
      return nil
    }

    private var previousOp: Character?

    private mutating func consumeNumber() -> Double? {
      guard position < tokens.count, case let .number(value) = tokens[position] else {
        return nil
      }
      position += 1
      return value
    }

    private mutating func match(_ token: Token) -> Bool {
      guard position < tokens.count else {
        return false
      }
      switch (token, tokens[position]) {
      case (.lparen, .lparen), (.rparen, .rparen):
        position += 1
        return true
      case let (.op(expected), .op(actual)) where expected == actual:
        previousOp = actual
        position += 1
        return true
      default:
        return false
      }
    }
  }
}
