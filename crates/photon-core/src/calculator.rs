//! Local calculator and unit conversions. No network, no AI.

#[derive(Debug, Clone, PartialEq)]
pub struct CalculatorResult {
    pub expression: String,
    pub value: String,
    pub operation_label: String,
    pub word_form: Option<String>,
}

impl CalculatorResult {
    pub fn row_title(&self) -> String {
        format!("{} → {}", self.expression, self.value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalculatorDisplayModel {
    pub command_id: String,
    pub expression: String,
    pub value: String,
    pub expression_caption: String,
    pub value_caption: Option<String>,
}

impl CalculatorDisplayModel {
    pub const SECTION_TITLE: &'static str = "Calculator";

    pub fn from_result(result: &CalculatorResult, command_id: impl Into<String>) -> Self {
        Self {
            command_id: command_id.into(),
            expression: result.expression.clone(),
            value: result.value.clone(),
            expression_caption: result.operation_label.clone(),
            value_caption: result.word_form.clone(),
        }
    }
}

pub struct CalculatorEngine;

impl CalculatorEngine {
    pub fn evaluate(raw_query: &str) -> Option<CalculatorResult> {
        let query = raw_query.trim();
        if query.is_empty() {
            return None;
        }
        if let Some(conversion) = evaluate_conversion(query) {
            return Some(conversion);
        }
        evaluate_math(query)
    }
}

fn compact(input: &str) -> String {
    input.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn format_number(value: f64) -> String {
    if !value.is_finite() {
        return value.to_string();
    }
    if value.fract().abs() < 1e-10 {
        return format!("{}", value as i64);
    }
    let mut s = format!("{value:.10}");
    while s.contains('.') && s.ends_with('0') {
        s.pop();
    }
    if s.ends_with('.') {
        s.pop();
    }
    s
}

fn spoken_form(value: f64) -> Option<String> {
    if !(value.is_finite()) || value.fract().abs() > 1e-9 || value.abs() > 1000.0 {
        return None;
    }
    let n = value.round() as i64;
    Some(number_word(n))
}

fn number_word(n: i64) -> String {
    if n < 0 {
        return format!("Negative {}", number_word(-n).to_lowercase());
    }
    const ONES: [&str; 20] = [
        "Zero",
        "One",
        "Two",
        "Three",
        "Four",
        "Five",
        "Six",
        "Seven",
        "Eight",
        "Nine",
        "Ten",
        "Eleven",
        "Twelve",
        "Thirteen",
        "Fourteen",
        "Fifteen",
        "Sixteen",
        "Seventeen",
        "Eighteen",
        "Nineteen",
    ];
    const TENS: [&str; 10] = [
        "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety",
    ];
    match n {
        0..=19 => ONES[n as usize].to_string(),
        20..=99 => {
            let t = (n / 10) as usize;
            let o = n % 10;
            if o == 0 {
                TENS[t].to_string()
            } else {
                format!("{}-{}", TENS[t], ONES[o as usize].to_lowercase())
            }
        }
        100..=999 => {
            let h = n / 100;
            let rest = n % 100;
            if rest == 0 {
                format!("{} hundred", ONES[h as usize])
            } else {
                format!(
                    "{} hundred {}",
                    ONES[h as usize],
                    number_word(rest).to_lowercase()
                )
            }
        }
        1000 => "One thousand".into(),
        _ => n.to_string(),
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Token {
    Number(f64),
    Op(char),
    LParen,
    RParen,
}

fn tokenize(input: &str) -> Option<Vec<Token>> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut pending_unary = true;
    while i < chars.len() {
        let ch = chars[i];
        if ch.is_whitespace() {
            i += 1;
            continue;
        }
        if ch.is_ascii_digit() || ch == '.' {
            let start = i;
            let mut saw_dot = ch == '.';
            i += 1;
            while i < chars.len() {
                if chars[i].is_ascii_digit() {
                    i += 1;
                } else if chars[i] == '.' && !saw_dot {
                    saw_dot = true;
                    i += 1;
                } else {
                    break;
                }
            }
            let slice: String = chars[start..i].iter().collect();
            let value: f64 = slice.parse().ok()?;
            tokens.push(Token::Number(value));
            pending_unary = false;
            continue;
        }
        match ch {
            '(' => {
                tokens.push(Token::LParen);
                pending_unary = true;
                i += 1;
            }
            ')' => {
                tokens.push(Token::RParen);
                pending_unary = false;
                i += 1;
            }
            '+' | '-' | '*' | '/' | '^' | '%' => {
                if ch == '-' && pending_unary {
                    tokens.push(Token::Number(0.0));
                }
                tokens.push(Token::Op(ch));
                pending_unary = true;
                i += 1;
            }
            _ => return None,
        }
    }
    Some(tokens)
}

fn contains_operator(tokens: &[Token]) -> bool {
    tokens.iter().any(|t| matches!(t, Token::Op(_)))
}

struct Parser<'a> {
    tokens: &'a [Token],
    index: usize,
    last_op: Option<char>,
}

impl<'a> Parser<'a> {
    fn parse_expression(&mut self) -> Option<f64> {
        self.parse_add()
    }

    fn parse_add(&mut self) -> Option<f64> {
        let mut left = self.parse_mul()?;
        while let Some(Token::Op(op @ ('+' | '-'))) = self.peek() {
            self.index += 1;
            self.last_op = Some(op);
            let right = self.parse_mul()?;
            left = if op == '+' {
                left + right
            } else {
                left - right
            };
        }
        Some(left)
    }

    fn parse_mul(&mut self) -> Option<f64> {
        let mut left = self.parse_pow()?;
        while let Some(Token::Op(op @ ('*' | '/' | '%'))) = self.peek() {
            self.index += 1;
            self.last_op = Some(op);
            let right = self.parse_pow()?;
            left = match op {
                '*' => left * right,
                '/' => {
                    if right == 0.0 {
                        return None;
                    }
                    left / right
                }
                '%' => {
                    if right == 0.0 {
                        return None;
                    }
                    left % right
                }
                _ => unreachable!(),
            };
        }
        Some(left)
    }

    fn parse_pow(&mut self) -> Option<f64> {
        let left = self.parse_primary()?;
        if let Some(Token::Op('^')) = self.peek() {
            self.index += 1;
            self.last_op = Some('^');
            let right = self.parse_pow()?;
            Some(left.powf(right))
        } else {
            Some(left)
        }
    }

    fn parse_primary(&mut self) -> Option<f64> {
        match self.peek()? {
            Token::Number(n) => {
                self.index += 1;
                Some(n)
            }
            Token::LParen => {
                self.index += 1;
                let value = self.parse_expression()?;
                match self.peek() {
                    Some(Token::RParen) => {
                        self.index += 1;
                        Some(value)
                    }
                    _ => None,
                }
            }
            _ => None,
        }
    }

    fn peek(&self) -> Option<Token> {
        self.tokens.get(self.index).copied()
    }
}

fn op_label(op: char) -> &'static str {
    match op {
        '+' => "Add",
        '-' => "Subtract",
        '*' => "Multiply",
        '/' => "Divide",
        '^' => "Power",
        '%' => "Modulo",
        _ => "Calculate",
    }
}

fn evaluate_math(input: &str) -> Option<CalculatorResult> {
    let tokens = tokenize(input)?;
    if tokens.is_empty() || !contains_operator(&tokens) {
        return None;
    }
    let mut parser = Parser {
        tokens: &tokens,
        index: 0,
        last_op: None,
    };
    let value = parser.parse_expression()?;
    if parser.index != tokens.len() || !value.is_finite() {
        return None;
    }
    Some(CalculatorResult {
        expression: compact(input),
        value: format_number(value),
        operation_label: parser.last_op.map(op_label).unwrap_or("Calculate").into(),
        word_form: spoken_form(value),
    })
}

#[derive(Clone, Copy)]
enum Unit {
    Meter(f64),
    Gram(f64),
    Celsius,
    Fahrenheit,
    Kelvin,
    Second(f64),
    Byte(f64),
}

fn resolve_unit(raw: &str) -> Option<Unit> {
    let t = raw.trim().to_lowercase();
    let t = t.trim_end_matches('.');
    Some(match t {
        "m" | "meter" | "meters" | "metre" | "metres" => Unit::Meter(1.0),
        "km" | "kilometer" | "kilometers" => Unit::Meter(1000.0),
        "cm" | "centimeter" | "centimeters" => Unit::Meter(0.01),
        "mm" | "millimeter" | "millimeters" => Unit::Meter(0.001),
        "mi" | "mile" | "miles" => Unit::Meter(1609.344),
        "ft" | "foot" | "feet" => Unit::Meter(0.3048),
        "in" | "inch" | "inches" => Unit::Meter(0.0254),
        "yd" | "yard" | "yards" => Unit::Meter(0.9144),
        "g" | "gram" | "grams" => Unit::Gram(1.0),
        "kg" | "kilogram" | "kilograms" => Unit::Gram(1000.0),
        "lb" | "lbs" | "pound" | "pounds" => Unit::Gram(453.59237),
        "oz" | "ounce" | "ounces" => Unit::Gram(28.349523125),
        "c" | "cel" | "celsius" => Unit::Celsius,
        "f" | "fah" | "fahrenheit" => Unit::Fahrenheit,
        "k" | "kelvin" => Unit::Kelvin,
        "s" | "sec" | "secs" | "second" | "seconds" => Unit::Second(1.0),
        "min" | "mins" | "minute" | "minutes" => Unit::Second(60.0),
        "h" | "hr" | "hrs" | "hour" | "hours" => Unit::Second(3600.0),
        "d" | "day" | "days" => Unit::Second(86400.0),
        "b" | "byte" | "bytes" => Unit::Byte(1.0),
        "kb" => Unit::Byte(1000.0),
        "mb" => Unit::Byte(1_000_000.0),
        "gb" => Unit::Byte(1_000_000_000.0),
        "tb" => Unit::Byte(1_000_000_000_000.0),
        "kib" => Unit::Byte(1024.0),
        "mib" => Unit::Byte(1024.0 * 1024.0),
        "gib" => Unit::Byte(1024.0 * 1024.0 * 1024.0),
        _ => return None,
    })
}

fn to_canonical(amount: f64, unit: Unit) -> Option<(u8, f64)> {
    match unit {
        Unit::Meter(f) => Some((0, amount * f)),
        Unit::Gram(f) => Some((1, amount * f)),
        Unit::Celsius => Some((2, amount)),
        Unit::Fahrenheit => Some((2, (amount - 32.0) * 5.0 / 9.0)),
        Unit::Kelvin => Some((2, amount - 273.15)),
        Unit::Second(f) => Some((3, amount * f)),
        Unit::Byte(f) => Some((4, amount * f)),
    }
}

fn from_canonical(kind: u8, canonical: f64, unit: Unit) -> Option<f64> {
    match (kind, unit) {
        (0, Unit::Meter(f)) => Some(canonical / f),
        (1, Unit::Gram(f)) => Some(canonical / f),
        (2, Unit::Celsius) => Some(canonical),
        (2, Unit::Fahrenheit) => Some(canonical * 9.0 / 5.0 + 32.0),
        (2, Unit::Kelvin) => Some(canonical + 273.15),
        (3, Unit::Second(f)) => Some(canonical / f),
        (4, Unit::Byte(f)) => Some(canonical / f),
        _ => None,
    }
}

fn parse_amount_unit(text: &str) -> Option<(f64, Unit)> {
    let trimmed = text.trim();
    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    if parts.len() >= 2 {
        let number = parts[..parts.len() - 1].join(" ");
        let amount: f64 = number.parse().ok()?;
        let unit = resolve_unit(parts[parts.len() - 1])?;
        return Some((amount, unit));
    }
    let mut split = 0usize;
    for (i, ch) in trimmed.char_indices() {
        if ch.is_ascii_digit() || ch == '.' || ch == '+' || ch == '-' {
            split = i + ch.len_utf8();
        } else {
            break;
        }
    }
    if split == 0 || split >= trimmed.len() {
        return None;
    }
    let amount: f64 = trimmed[..split].parse().ok()?;
    let unit = resolve_unit(&trimmed[split..])?;
    Some((amount, unit))
}

fn evaluate_conversion(input: &str) -> Option<CalculatorResult> {
    let lowered = input.to_lowercase();
    let sep = lowered.find(" to ").or_else(|| lowered.find(" in "))?;
    let sep_len = if lowered[sep..].starts_with(" to ") {
        4
    } else {
        4
    };
    let left = input[..sep].trim();
    let right = input[sep + sep_len..].trim();
    let (amount, from) = parse_amount_unit(left)?;
    let to = resolve_unit(right)?;
    let (kind, canonical) = to_canonical(amount, from)?;
    let converted = from_canonical(kind, canonical, to)?;
    if !converted.is_finite() {
        return None;
    }
    Some(CalculatorResult {
        expression: compact(input),
        value: format_number(converted),
        operation_label: "Convert".into(),
        word_form: spoken_form(converted),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn division_and_power() {
        let result = CalculatorEngine::evaluate("30/5").unwrap();
        assert_eq!(result.value, "6");
        assert_eq!(result.operation_label, "Divide");
        assert_eq!(result.word_form.as_deref(), Some("Six"));
        assert_eq!(CalculatorEngine::evaluate("(2+3)*4").unwrap().value, "20");
        assert_eq!(CalculatorEngine::evaluate("2^10").unwrap().value, "1024");
        assert_eq!(
            CalculatorEngine::evaluate("2^10").unwrap().operation_label,
            "Power"
        );
    }

    #[test]
    fn temperature() {
        assert_eq!(CalculatorEngine::evaluate("32 f to c").unwrap().value, "0");
        assert_eq!(
            CalculatorEngine::evaluate("212 f to c").unwrap().value,
            "100"
        );
    }

    #[test]
    fn non_expression() {
        assert!(CalculatorEngine::evaluate("safari").is_none());
        assert!(CalculatorEngine::evaluate("").is_none());
        assert!(CalculatorEngine::evaluate("1/0").is_none());
    }

    #[test]
    fn two_plus_two_display() {
        let result = CalculatorEngine::evaluate("2 + 2").unwrap();
        let hero = CalculatorDisplayModel::from_result(&result, "calc");
        assert_eq!(hero.expression, "2 + 2");
        assert_eq!(hero.value, "4");
        assert_eq!(hero.expression_caption, "Add");
        assert_eq!(hero.value_caption.as_deref(), Some("Four"));
    }
}
