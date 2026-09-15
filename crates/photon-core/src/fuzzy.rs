//! Case-insensitive subsequence matcher with a score in `(0, 1]`.

pub struct FuzzyMatcher;

impl FuzzyMatcher {
    pub fn matches(query: &str, candidate: &str) -> bool {
        Self::score(query, candidate).is_some()
    }

    pub fn score(query: &str, candidate: &str) -> Option<f64> {
        let needle: Vec<char> = query.to_lowercase().chars().collect();
        let hay: Vec<char> = candidate.to_lowercase().chars().collect();
        let original: Vec<char> = candidate.chars().collect();

        if needle.is_empty() {
            return Some(1.0);
        }
        if hay.is_empty() {
            return None;
        }

        let mut hay_index = 0usize;
        let mut consecutive = 0usize;
        let mut max_consecutive = 0usize;
        let mut first_index: Option<usize> = None;
        let mut word_start_hits = 0usize;

        for ch in needle.iter() {
            let mut found = false;
            while hay_index < hay.len() {
                if hay[hay_index] == *ch {
                    if first_index.is_none() {
                        first_index = Some(hay_index);
                    }
                    if hay_index == 0 || is_word_start(&original, hay_index) {
                        word_start_hits += 1;
                    }
                    consecutive += 1;
                    max_consecutive = max_consecutive.max(consecutive);
                    hay_index += 1;
                    found = true;
                    break;
                }
                consecutive = 0;
                hay_index += 1;
            }
            if !found {
                return None;
            }
        }

        let coverage = needle.len() as f64 / hay.len() as f64;
        let consecutive_bonus = max_consecutive as f64 / needle.len() as f64;
        let prefix_bonus = if first_index == Some(0) { 0.25 } else { 0.0 };
        let word_bonus = word_start_hits as f64 / needle.len() as f64 * 0.2;
        let exact_bonus = if query.eq_ignore_ascii_case(candidate) {
            0.35
        } else {
            0.0
        };
        let span = hay_index - first_index.unwrap_or(0);
        let compactness =
            1.0 - (span.saturating_sub(needle.len())) as f64 / hay.len().max(1) as f64;

        let raw = 0.35 * coverage
            + 0.25 * consecutive_bonus
            + 0.15 * compactness.max(0.0)
            + prefix_bonus
            + word_bonus
            + exact_bonus;
        Some(raw.min(1.0))
    }
}

fn is_word_start(chars: &[char], index: usize) -> bool {
    if index == 0 {
        return true;
    }
    let previous = chars[index - 1];
    if previous.is_whitespace() || "-_./".contains(previous) {
        return true;
    }
    let current = chars[index];
    previous.is_lowercase() && current.is_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_query_matches() {
        assert_eq!(FuzzyMatcher::score("", "Safari"), Some(1.0));
    }

    #[test]
    fn subsequence_and_exact() {
        assert!(FuzzyMatcher::matches("saf", "Safari"));
        assert!(FuzzyMatcher::score("Safari", "Safari").unwrap() >= 0.9);
        assert!(FuzzyMatcher::score("saf", "Safari").unwrap() > 0.3);
        assert!(FuzzyMatcher::score("zzz", "Safari").is_none());
    }
}
