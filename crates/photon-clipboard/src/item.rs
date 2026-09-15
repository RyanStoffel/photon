use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClipboardItemKind {
    Text,
    Link,
    Image,
    File,
}

impl ClipboardItemKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Text => "Text",
            Self::Link => "Link",
            Self::Image => "Image",
            Self::File => "File",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClipboardRetention {
    OneDay,
    SevenDays,
    ThirtyDays,
    Forever,
}

impl ClipboardRetention {
    pub fn from_days(days: i32) -> Self {
        match days {
            1 => Self::OneDay,
            7 => Self::SevenDays,
            0 => Self::Forever,
            _ => Self::ThirtyDays,
        }
    }

    pub fn days(self) -> i32 {
        match self {
            Self::OneDay => 1,
            Self::SevenDays => 7,
            Self::ThirtyDays => 30,
            Self::Forever => 0,
        }
    }

    pub fn cutoff_unix(self, now: f64) -> Option<f64> {
        match self {
            Self::Forever => None,
            other => Some(now - f64::from(other.days()) * 86400.0),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ClipboardPasteBehavior {
    Paste,
    Copy,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClipboardSettings {
    pub is_enabled: bool,
    pub retention: ClipboardRetention,
    pub max_items: u32,
    pub excluded_bundle_ids: Vec<String>,
    pub paste_behavior: ClipboardPasteBehavior,
}

impl Default for ClipboardSettings {
    fn default() -> Self {
        Self {
            is_enabled: true,
            retention: ClipboardRetention::ThirtyDays,
            max_items: 500,
            excluded_bundle_ids: vec![
                "com.1password.1password".into(),
                "com.agilebits.onepassword7".into(),
                "com.bitwarden.desktop".into(),
                "com.apple.keychainaccess".into(),
                "org.keepassxc.keepassxc".into(),
            ],
            paste_behavior: ClipboardPasteBehavior::Paste,
        }
    }
}

impl ClipboardSettings {
    pub fn is_excluded(&self, bundle_id: Option<&str>) -> bool {
        let Some(bundle_id) = bundle_id.filter(|s| !s.is_empty()) else {
            return false;
        };
        self.excluded_bundle_ids
            .iter()
            .any(|id| id.eq_ignore_ascii_case(bundle_id))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClipboardItem {
    pub id: Uuid,
    pub kind: ClipboardItemKind,
    pub created_at: f64,
    pub copied_at: f64,
    pub is_pinned: bool,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub text: Option<String>,
    pub is_text_truncated: bool,
    pub has_rich_text: bool,
    pub has_image: bool,
    pub image_width: Option<u32>,
    pub image_height: Option<u32>,
    pub file_paths: Vec<String>,
    pub byte_count: u64,
    pub content_hash: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_blob: Option<Vec<u8>>,
}

impl ClipboardItem {
    pub const INLINE_TEXT_LIMIT: usize = 16384;

    pub fn text(value: &str, at: f64, is_pinned: bool) -> Self {
        let truncated = value.chars().count() > Self::INLINE_TEXT_LIMIT;
        let inline = if truncated {
            value.chars().take(Self::INLINE_TEXT_LIMIT).collect()
        } else {
            value.to_string()
        };
        Self {
            id: Uuid::new_v4(),
            kind: if ClipboardContent::is_link(value) {
                ClipboardItemKind::Link
            } else {
                ClipboardItemKind::Text
            },
            created_at: at,
            copied_at: at,
            is_pinned,
            source_bundle_id: None,
            source_app_name: None,
            text: Some(inline),
            is_text_truncated: truncated,
            has_rich_text: false,
            has_image: false,
            image_width: None,
            image_height: None,
            file_paths: Vec::new(),
            byte_count: value.len() as u64,
            content_hash: ClipboardContent::hash_text(value),
            image_blob: None,
        }
    }

    pub fn image(png: Vec<u8>, width: u32, height: u32, at: f64) -> Self {
        let hash = ClipboardContent::hash_image(&png);
        Self {
            id: Uuid::new_v4(),
            kind: ClipboardItemKind::Image,
            created_at: at,
            copied_at: at,
            is_pinned: false,
            source_bundle_id: None,
            source_app_name: None,
            text: None,
            is_text_truncated: false,
            has_rich_text: false,
            has_image: true,
            image_width: Some(width),
            image_height: Some(height),
            file_paths: Vec::new(),
            byte_count: png.len() as u64,
            content_hash: hash,
            image_blob: Some(png),
        }
    }

    pub fn files(paths: Vec<String>, at: f64) -> Self {
        let hash = ClipboardContent::hash_files(&paths);
        Self {
            id: Uuid::new_v4(),
            kind: ClipboardItemKind::File,
            created_at: at,
            copied_at: at,
            is_pinned: false,
            source_bundle_id: None,
            source_app_name: None,
            text: None,
            is_text_truncated: false,
            has_rich_text: false,
            has_image: false,
            image_width: None,
            image_height: None,
            file_paths: paths.clone(),
            byte_count: 0,
            content_hash: hash,
            image_blob: None,
        }
    }

    pub fn title(&self) -> String {
        match self.kind {
            ClipboardItemKind::Text | ClipboardItemKind::Link => {
                ClipboardContent::first_line(self.text.as_deref().unwrap_or(""), 120)
            }
            ClipboardItemKind::Image => "Image".into(),
            ClipboardItemKind::File => {
                if self.file_paths.len() == 1 {
                    std::path::Path::new(&self.file_paths[0])
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("File")
                        .to_string()
                } else {
                    format!("{} files", self.file_paths.len())
                }
            }
        }
    }

    pub fn searchable_body(&self) -> String {
        match self.kind {
            ClipboardItemKind::Text | ClipboardItemKind::Link => {
                self.text.clone().unwrap_or_default()
            }
            ClipboardItemKind::Image => String::new(),
            ClipboardItemKind::File => self.file_paths.join("\n"),
        }
    }
}

pub struct ClipboardContent;

impl ClipboardContent {
    pub fn is_link(text: &str) -> bool {
        let trimmed = text.trim();
        if trimmed.is_empty() || trimmed.chars().any(char::is_whitespace) {
            return false;
        }
        let lower = trimmed.to_ascii_lowercase();
        (lower.starts_with("http://")
            || lower.starts_with("https://")
            || lower.starts_with("ftp://"))
            && trimmed.contains('.')
    }

    pub fn first_line(text: &str, limit: usize) -> String {
        let line = text
            .lines()
            .map(str::trim)
            .find(|l| !l.is_empty())
            .unwrap_or("");
        let collapsed: String = line.split_whitespace().collect::<Vec<_>>().join(" ");
        if collapsed.chars().count() > limit {
            let mut out: String = collapsed.chars().take(limit).collect();
            out.push('…');
            out
        } else {
            collapsed
        }
    }

    pub fn hash_text(text: &str) -> String {
        format!("t:{}", fnv1a(text.as_bytes()))
    }

    pub fn hash_image(data: &[u8]) -> String {
        format!("i:{}", fnv1a(data))
    }

    pub fn hash_files(paths: &[String]) -> String {
        let mut sorted = paths.to_vec();
        sorted.sort();
        format!("f:{}", fnv1a(sorted.join("\u{0}").as_bytes()))
    }
}

fn fnv1a(bytes: &[u8]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{hash:x}")
}
