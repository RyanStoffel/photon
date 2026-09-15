use photon_core::FuzzyMatcher;

pub struct FileFuzzyMatcher;

impl FileFuzzyMatcher {
    pub fn normalize(text: &str) -> String {
        text.chars()
            .filter(|c| c.is_alphanumeric())
            .flat_map(|c| c.to_lowercase())
            .collect()
    }

    pub fn score(query: &str, candidate: &str) -> Option<f64> {
        let needle = Self::normalize(query);
        if needle.is_empty() {
            return Some(1.0);
        }
        let hay = Self::normalize(candidate);
        if hay.is_empty() {
            return None;
        }
        if hay == needle {
            return Some(1.0);
        }
        FuzzyMatcher::score(&needle, &hay)
    }
}
