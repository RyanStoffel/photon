use serde::{Deserialize, Serialize};

/// Combines frequency and recency into a single ranking score.
///
/// `score = log2(1 + uses) * 0.5^(days / halfLifeDays)`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrecencyStore {
    pub half_life_days: f64,
    pub records: std::collections::BTreeMap<String, FrecencyRecord>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrecencyRecord {
    pub count: u32,
    pub last_used_unix: f64,
}

impl Default for FrecencyStore {
    fn default() -> Self {
        Self {
            half_life_days: 7.0,
            records: Default::default(),
        }
    }
}

impl FrecencyStore {
    pub fn record_use(&mut self, id: &str, at_unix: f64) {
        self.records
            .entry(id.to_string())
            .and_modify(|existing| {
                existing.count += 1;
                existing.last_used_unix = at_unix;
            })
            .or_insert(FrecencyRecord {
                count: 1,
                last_used_unix: at_unix,
            });
    }

    pub fn score(&self, id: &str, now_unix: f64) -> f64 {
        match self.records.get(id) {
            Some(record) => Self::score_record(record, now_unix, self.half_life_days),
            None => 0.0,
        }
    }

    pub fn score_record(record: &FrecencyRecord, now_unix: f64, half_life_days: f64) -> f64 {
        let days = ((now_unix - record.last_used_unix) / 86400.0).max(0.0);
        let recency = 0.5_f64.powf(days / half_life_days.max(0.001));
        (1.0 + f64::from(record.count)).log2() * recency
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unused_ids_score_zero() {
        let store = FrecencyStore::default();
        assert_eq!(store.score("missing", 0.0), 0.0);
    }

    #[test]
    fn more_uses_rank_higher() {
        let mut store = FrecencyStore::default();
        store.record_use("a", 0.0);
        store.record_use("b", 0.0);
        store.record_use("b", 0.0);
        assert!(store.score("b", 0.0) > store.score("a", 0.0));
    }
}
