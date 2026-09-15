//! Global hotkey registration. Carbon `RegisterEventHotKey` on macOS.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HotkeyCombo {
    pub key_code: u16,
    pub modifiers: u32,
}

impl HotkeyCombo {
    pub fn launcher_default() -> Self {
        Self {
            key_code: 49,   // space
            modifiers: 256, // cmd
        }
    }

    pub fn clipboard_default() -> Self {
        Self {
            key_code: 9,          // V
            modifiers: 256 + 512, // cmd+shift
        }
    }
}

pub enum HotkeyAction {
    ToggleLauncher,
    ShowClipboard,
}
