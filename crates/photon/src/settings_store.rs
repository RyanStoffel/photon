use std::fs;
use std::path::{Path, PathBuf};

use photon_core::PhotonSettings;

pub struct SettingsStore {
    pub path: PathBuf,
    pub settings: PhotonSettings,
}

impl SettingsStore {
    pub fn load(root: impl AsRef<Path>) -> Self {
        let path = root.as_ref().join("settings.json");
        let settings = fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        Self { path, settings }
    }

    pub fn save(&self) -> std::io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(
            &self.path,
            serde_json::to_vec_pretty(&self.settings).expect("settings json"),
        )
    }

    pub fn support_dir() -> PathBuf {
        if let Ok(root) = std::env::var("PHOTON_ISOLATED_DATA_ROOT") {
            if !root.is_empty() {
                return PathBuf::from(root);
            }
        }
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("Photon")
    }
}
