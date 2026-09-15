import Foundation

enum NumberWords {
  private static let ones = [
    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
    "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
  ]
  private static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

  static func spokenForm(for value: Double) -> String? {
    guard value.isFinite, value >= 0, value <= 999_999, abs(value - value.rounded()) < 1e-9 else {
      return nil
    }
    let intValue = Int(value.rounded())
    if intValue < ones.count {
      return ones[intValue]
    }
    if intValue < 100 {
      let remainder = intValue % 10
      let ten = intValue / 10
      if remainder == 0 {
        return tens[ten]
      }
      return "\(tens[ten])-\(ones[remainder].lowercased())".replacingOccurrences(of: "-zero", with: "")
    }
    if intValue < 1000 {
      let hundreds = intValue / 100
      let remainder = intValue % 100
      if remainder == 0 {
        return "\(ones[hundreds]) Hundred"
      }
      return "\(ones[hundreds]) Hundred \(spokenForm(for: Double(remainder)) ?? "")"
    }
    if intValue < 1_000_000 {
      let thousands = intValue / 1000
      let remainder = intValue % 1000
      let head = "\(spokenForm(for: Double(thousands)) ?? "") Thousand"
      if remainder == 0 {
        return head
      }
      return "\(head) \(spokenForm(for: Double(remainder)) ?? "")"
    }
    return nil
  }
}
