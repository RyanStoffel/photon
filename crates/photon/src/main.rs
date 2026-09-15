//! Photon — macOS launcher. The GPUI UI compiles on macOS; headless logic is in
//! photon-core / photon-clipboard / photon-files and is tested everywhere.

#![cfg_attr(not(target_os = "macos"), allow(dead_code))]

mod apps;
mod clipboard_os;
mod hotkey;
mod notes;
mod runtime;
mod screenshot;
mod settings_store;
mod theme;
mod window_cmds;

#[cfg(target_os = "macos")]
mod macos_ui;

fn main() {
    if let Err(error) = runtime::run() {
        eprintln!("Photon failed to start: {error}");
        std::process::exit(1);
    }
}
