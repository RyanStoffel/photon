use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq)]
pub struct FileResult {
    pub path: String,
    pub display_name: String,
    pub file_name: String,
    pub kind: String,
    pub content_type: Option<String>,
    pub is_folder: bool,
    pub is_application: bool,
    pub size: Option<u64>,
    pub created: Option<f64>,
    pub modified: Option<f64>,
    pub last_used: Option<f64>,
}

impl FileResult {
    pub fn from_path(path: impl AsRef<Path>) -> Option<Self> {
        let path = path.as_ref();
        let meta = std::fs::metadata(path).ok()?;
        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();
        let is_folder = meta.is_dir();
        let is_application = path.extension().and_then(|e| e.to_str()) == Some("app");
        Some(Self {
            path: path.to_string_lossy().into_owned(),
            display_name: file_name.clone(),
            file_name,
            kind: if is_folder {
                "Folder".into()
            } else {
                "Document".into()
            },
            content_type: None,
            is_folder,
            is_application,
            size: if is_folder { None } else { Some(meta.len()) },
            created: meta.created().ok().and_then(system_time_unix),
            modified: meta.modified().ok().and_then(system_time_unix),
            last_used: None,
        })
    }

    pub fn stem(&self) -> &str {
        let base = if self.display_name.is_empty() {
            &self.file_name
        } else {
            &self.display_name
        };
        if self.is_folder {
            return base;
        }
        Path::new(base)
            .file_stem()
            .and_then(|s| s.to_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(base)
    }
}

fn system_time_unix(time: SystemTime) -> Option<f64> {
    Some(time.duration_since(UNIX_EPOCH).ok()?.as_secs_f64())
}
