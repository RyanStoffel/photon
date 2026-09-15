use serde::{Deserialize, Serialize};

use crate::layout::LauncherPanelWidth;
use crate::position::LauncherStoredPosition;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum AppAppearance {
    #[default]
    System,
    Light,
    Dark,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhotonSettings {
    pub hotkey_key_code: u16,
    pub hotkey_modifiers: u32,
    pub clipboard_hotkey_key_code: u16,
    pub clipboard_hotkey_modifiers: u32,
    pub launch_at_login: bool,
    pub shows_suggestions: bool,
    pub panel_width: LauncherPanelWidth,
    pub appearance: AppAppearance,
    pub launcher_position: Option<LauncherStoredPosition>,
    pub clipboard_enabled: bool,
    pub clipboard_retention_days: i32,
    pub clipboard_max_items: u32,
    pub clipboard_excluded_bundle_ids: Vec<String>,
    pub clipboard_paste_behavior: String,
    pub files_scope: String,
    pub files_extra_folders: Vec<String>,
    pub files_excluded_folders: Vec<String>,
    pub files_search_contents: bool,
    pub files_max_results: u32,
    pub files_default_action: String,
    pub files_inline_results: bool,
    pub notes_hotkey_enabled: bool,
    pub hyper_key_enabled: bool,
}

impl Default for PhotonSettings {
    fn default() -> Self {
        Self {
            // Cmd+Space — Carbon virtual key 49 (space), cmdKey = 256
            hotkey_key_code: 49,
            hotkey_modifiers: 256,
            // Cmd+Shift+V — key 9, cmd+shift
            clipboard_hotkey_key_code: 9,
            clipboard_hotkey_modifiers: 256 + 512,
            launch_at_login: false,
            shows_suggestions: false,
            panel_width: LauncherPanelWidth::Regular,
            appearance: AppAppearance::System,
            launcher_position: None,
            clipboard_enabled: true,
            clipboard_retention_days: 30,
            clipboard_max_items: 500,
            clipboard_excluded_bundle_ids: vec![
                "com.1password.1password".into(),
                "com.agilebits.onepassword7".into(),
                "com.bitwarden.desktop".into(),
                "com.apple.keychainaccess".into(),
                "org.keepassxc.keepassxc".into(),
            ],
            clipboard_paste_behavior: "paste".into(),
            files_scope: "home".into(),
            files_extra_folders: Vec::new(),
            files_excluded_folders: Vec::new(),
            files_search_contents: false,
            files_max_results: 50,
            files_default_action: "open".into(),
            files_inline_results: true,
            notes_hotkey_enabled: false,
            hyper_key_enabled: true,
        }
    }
}
