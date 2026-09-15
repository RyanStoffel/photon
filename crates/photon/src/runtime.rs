use crate::screenshot;
use crate::settings_store::SettingsStore;

pub fn run() -> Result<(), String> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = SettingsStore::support_dir();
        let _ = screenshot::current_scenario();
        Err("Photon requires macOS 14 or later".into())
    }
    #[cfg(target_os = "macos")]
    {
        crate::macos_ui::run()
    }
}
