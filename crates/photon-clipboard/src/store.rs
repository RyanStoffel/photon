use std::fs;
use std::path::{Path, PathBuf};

use crate::history::ClipboardHistory;
use crate::item::ClipboardItem;

/// JSON index plus optional image blobs next to it.
pub struct ClipboardStore {
    pub path: PathBuf,
}

impl ClipboardStore {
    pub fn new(root: impl AsRef<Path>) -> Self {
        Self {
            path: root.as_ref().join("clipboard-index.json"),
        }
    }

    pub fn load(&self) -> ClipboardHistory {
        let Ok(bytes) = fs::read(&self.path) else {
            return ClipboardHistory::default();
        };
        serde_json::from_slice::<Vec<ClipboardItem>>(&bytes)
            .map(ClipboardHistory::new)
            .unwrap_or_default()
    }

    pub fn save(&self, history: &ClipboardHistory) -> std::io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let bytes = serde_json::to_vec_pretty(&history.items)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        fs::write(&self.path, bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::ClipboardItem;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn round_trip_text_image_files() {
        let dir = std::env::temp_dir().join(format!(
            "photon-cb-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let store = ClipboardStore::new(&dir);
        let mut history = ClipboardHistory::default();
        history.insert(ClipboardItem::text("hello", 1.0, false));
        history.insert(ClipboardItem::image(vec![1, 2, 3, 4], 8, 8, 2.0));
        history.insert(ClipboardItem::files(vec!["/tmp/a.pdf".into()], 3.0));
        store.save(&history).unwrap();
        let loaded = store.load();
        assert_eq!(loaded.items.len(), 3);
        assert!(loaded
            .items
            .iter()
            .any(|i| i.text.as_deref() == Some("hello")));
        assert!(loaded.items.iter().any(|i| i.has_image));
        assert!(loaded.items.iter().any(|i| !i.file_paths.is_empty()));
        fs::remove_dir_all(&dir).ok();
    }
}
