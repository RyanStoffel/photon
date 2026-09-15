use uuid::Uuid;

use crate::item::{ClipboardItem, ClipboardRetention};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InsertOutcome {
    Inserted,
    MovedToTop(Uuid),
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct ClipboardHistory {
    pub items: Vec<ClipboardItem>,
}

impl ClipboardHistory {
    pub fn new(mut items: Vec<ClipboardItem>) -> Self {
        items.sort_by(|a, b| b.copied_at.partial_cmp(&a.copied_at).unwrap());
        Self { items }
    }

    pub fn insert(&mut self, item: ClipboardItem) -> InsertOutcome {
        if let Some(index) = self
            .items
            .iter()
            .position(|existing| existing.content_hash == item.content_hash)
        {
            let mut existing = self.items.remove(index);
            existing.copied_at = existing.copied_at.max(item.copied_at);
            if item.source_bundle_id.is_some() {
                existing.source_bundle_id = item.source_bundle_id;
                existing.source_app_name = item.source_app_name;
            }
            let id = existing.id;
            self.items.insert(0, existing);
            InsertOutcome::MovedToTop(id)
        } else {
            let position = self
                .items
                .iter()
                .position(|existing| existing.copied_at <= item.copied_at)
                .unwrap_or(self.items.len());
            self.items.insert(position, item);
            InsertOutcome::Inserted
        }
    }

    pub fn touch(&mut self, id: Uuid, at: f64) -> bool {
        let Some(index) = self.items.iter().position(|item| item.id == id) else {
            return false;
        };
        let mut item = self.items.remove(index);
        item.copied_at = item.copied_at.max(at);
        self.items.insert(0, item);
        true
    }

    pub fn toggle_pin(&mut self, id: Uuid) -> Option<bool> {
        let item = self.items.iter_mut().find(|item| item.id == id)?;
        item.is_pinned = !item.is_pinned;
        Some(item.is_pinned)
    }

    pub fn remove(&mut self, id: Uuid) -> Option<ClipboardItem> {
        let index = self.items.iter().position(|item| item.id == id)?;
        Some(self.items.remove(index))
    }

    pub fn remove_all(&mut self) -> Vec<ClipboardItem> {
        std::mem::take(&mut self.items)
    }

    pub fn prune(
        &mut self,
        retention: ClipboardRetention,
        max_items: u32,
        now: f64,
    ) -> Vec<ClipboardItem> {
        let mut removed = Vec::new();
        if let Some(cutoff) = retention.cutoff_unix(now) {
            let (keep, drop): (Vec<_>, Vec<_>) = self
                .items
                .drain(..)
                .partition(|item| item.is_pinned || item.copied_at >= cutoff);
            removed.extend(drop);
            self.items = keep;
        }
        let limit = max_items.max(1) as usize;
        if self.items.len() > limit {
            let mut index = self.items.len();
            while self.items.len() > limit && index > 0 {
                index -= 1;
                if !self.items[index].is_pinned {
                    removed.push(self.items.remove(index));
                }
            }
        }
        removed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::{ClipboardContent, ClipboardSettings};

    const NOW: f64 = 1_800_000_000.0;

    fn text(value: &str, minutes_ago: f64, pinned: bool) -> ClipboardItem {
        ClipboardItem::text(value, NOW - minutes_ago * 60.0, pinned)
    }

    #[test]
    fn insert_newest_first_and_dedupe() {
        let mut history = ClipboardHistory::default();
        let first = text("same", 5.0, false);
        let id = first.id;
        assert_eq!(history.insert(first), InsertOutcome::Inserted);
        assert!(matches!(
            history.insert(text("same", 0.0, false)),
            InsertOutcome::MovedToTop(_)
        ));
        assert_eq!(history.items.len(), 1);
        assert_eq!(history.items[0].id, id);
        assert_eq!(history.items[0].copied_at, NOW);
    }

    #[test]
    fn retention_keeps_pinned() {
        let mut history = ClipboardHistory::default();
        history.insert(text("stale", 8.0 * 24.0 * 60.0, false));
        history.insert(text("stale pinned", 9.0 * 24.0 * 60.0, true));
        history.insert(text("fresh", 60.0, false));
        let removed = history.prune(ClipboardRetention::SevenDays, 100, NOW);
        assert_eq!(removed.len(), 1);
        assert_eq!(history.items.len(), 2);
    }

    #[test]
    fn hashes_stable() {
        let png = [0x89, 0x50, 0x4e, 0x47, 0x01, 0x02];
        assert_eq!(
            ClipboardContent::hash_image(&png),
            ClipboardContent::hash_image(&png)
        );
        assert_ne!(
            ClipboardContent::hash_files(&["/a".into(), "/b".into()]),
            ClipboardContent::hash_text("/a")
        );
        let settings = ClipboardSettings::default();
        assert!(settings.is_excluded(Some("com.1Password.1Password")));
        assert!(!settings.is_excluded(Some("com.apple.Safari")));
    }
}
