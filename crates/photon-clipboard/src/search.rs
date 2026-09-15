use photon_core::FuzzyMatcher;

use crate::item::ClipboardItem;

pub struct ClipboardSearch;

impl ClipboardSearch {
    pub fn rank(items: &[ClipboardItem], query: &str, now: f64) -> Vec<ClipboardItem> {
        let tokens: Vec<String> = query.split_whitespace().map(|t| t.to_lowercase()).collect();
        if tokens.is_empty() {
            let mut out = items.to_vec();
            out.sort_by(|lhs, rhs| match (lhs.is_pinned, rhs.is_pinned) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => rhs
                    .copied_at
                    .partial_cmp(&lhs.copied_at)
                    .unwrap_or(std::cmp::Ordering::Equal),
            });
            return out;
        }
        let mut scored: Vec<(f64, ClipboardItem)> = items
            .iter()
            .filter_map(|item| score(item, &tokens, now).map(|s| (s, item.clone())))
            .collect();
        scored.sort_by(|a, b| {
            b.0.partial_cmp(&a.0).unwrap().then(
                b.1.copied_at
                    .partial_cmp(&a.1.copied_at)
                    .unwrap_or(std::cmp::Ordering::Equal),
            )
        });
        scored.into_iter().map(|(_, item)| item).collect()
    }
}

fn score(item: &ClipboardItem, tokens: &[String], now: f64) -> Option<f64> {
    let title = item.title().to_lowercase();
    let body = item.searchable_body().to_lowercase();
    let app = item.source_app_name.as_deref().unwrap_or("").to_lowercase();
    let kind = item.kind.label().to_lowercase();
    let mut total = 0.0;
    for token in tokens {
        total += token_score(token, &title, &body, &app, &kind)?;
    }
    let relevance = total / tokens.len() as f64;
    let age_hours = ((now - item.copied_at) / 3600.0).max(0.0);
    let recency = 0.1 * 0.5_f64.powf(age_hours / 24.0);
    let pinned = if item.is_pinned { 0.1 } else { 0.0 };
    Some(relevance + recency + pinned)
}

fn token_score(token: &str, title: &str, body: &str, app: &str, kind: &str) -> Option<f64> {
    if !title.is_empty() {
        if let Some(pos) = title.find(token) {
            let mut score = 1.0;
            if pos == 0 {
                score += 0.3;
            } else if title
                .get(..pos)
                .and_then(|s| s.chars().last())
                .is_some_and(char::is_whitespace)
            {
                score += 0.15;
            }
            if title == token {
                score += 0.3;
            }
            return Some(score);
        }
    }
    if !body.is_empty() && body.contains(token) {
        return Some(0.7);
    }
    if !app.is_empty() && app.contains(token) {
        return Some(0.4);
    }
    if (kind == token || kind.starts_with(token)) && token.len() >= 3 {
        return Some(0.35);
    }
    if !title.is_empty() {
        if let Some(fuzzy) = FuzzyMatcher::score(token, title) {
            if fuzzy >= 0.3 {
                return Some(fuzzy * 0.5);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::ClipboardItem;

    #[test]
    fn empty_query_pins_first() {
        let now = 1000.0;
        let mut pinned = ClipboardItem::text("old", 10.0, true);
        pinned.copied_at = 10.0;
        let fresh = ClipboardItem::text("new", now, false);
        let ranked = ClipboardSearch::rank(&[fresh.clone(), pinned.clone()], "", now);
        assert_eq!(ranked[0].id, pinned.id);
        let filtered = ClipboardSearch::rank(&[fresh, pinned], "new", now);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].title(), "new");
    }
}
