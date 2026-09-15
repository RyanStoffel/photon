//! Colors matching the Swift Photon popover panel.

#[derive(Debug, Clone, Copy)]
pub struct Theme {
    pub background: u32,
    pub text: u32,
    pub secondary: u32,
    pub hairline: u32,
    pub selection: u32,
    pub accent: u32,
    pub card: u32,
    pub placeholder: u32,
}

impl Theme {
    pub fn light() -> Self {
        Self {
            background: 0xF5F5F7,
            text: 0x1D1D1F,
            secondary: 0x6E6E73,
            hairline: 0x3C3C4333,
            selection: 0xE8E8ED,
            accent: 0x0071E3,
            card: 0xE8E8ED,
            placeholder: 0x86868B,
        }
    }

    pub fn dark() -> Self {
        Self {
            background: 0x2C2C2E,
            text: 0xF5F5F7,
            secondary: 0xA1A1A6,
            hairline: 0xFFFFFF1A,
            selection: 0x3A3A3C,
            accent: 0x0A84FF,
            card: 0x3A3A3C,
            placeholder: 0x8E8E93,
        }
    }
}
