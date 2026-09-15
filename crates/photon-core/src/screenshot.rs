//! Deterministic UI states for automated screenshots and compact-bar assertions.

use crate::launcher::{LauncherSession, LauncherState};
use crate::layout::{Content, LauncherLayout};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScreenshotScenario {
    LauncherEmpty,
    LauncherRecs,
    LauncherQuery(String),
    Calculator,
    ClipboardEmpty,
    FilesEmpty,
    FilesQuery(String),
    SettingsAppearance,
    Notes,
}

impl ScreenshotScenario {
    pub fn parse(raw: &str) -> Option<Self> {
        if raw == "launcher-empty" {
            return Some(Self::LauncherEmpty);
        }
        if raw == "launcher-recs" {
            return Some(Self::LauncherRecs);
        }
        if let Some(q) = raw.strip_prefix("launcher-query:") {
            return Some(Self::LauncherQuery(q.to_string()));
        }
        if raw == "calculator" {
            return Some(Self::Calculator);
        }
        if raw == "clipboard-empty" {
            return Some(Self::ClipboardEmpty);
        }
        if raw == "files-empty" {
            return Some(Self::FilesEmpty);
        }
        if let Some(q) = raw.strip_prefix("files-query:") {
            return Some(Self::FilesQuery(q.to_string()));
        }
        if raw == "settings:appearance" || raw == "settings-appearance" {
            return Some(Self::SettingsAppearance);
        }
        if raw == "notes" {
            return Some(Self::Notes);
        }
        None
    }

    pub fn slug(&self) -> String {
        match self {
            Self::LauncherEmpty => "launcher-empty".into(),
            Self::LauncherRecs => "launcher-recs".into(),
            Self::LauncherQuery(q) => format!("launcher-query-{q}"),
            Self::Calculator => "calculator".into(),
            Self::ClipboardEmpty => "clipboard-empty".into(),
            Self::FilesEmpty => "files-empty".into(),
            Self::FilesQuery(q) => format!("files-query-{q}"),
            Self::SettingsAppearance => "settings-appearance".into(),
            Self::Notes => "notes".into(),
        }
    }

    pub fn apply(&self, state: &mut LauncherState) {
        state.show();
        match self {
            Self::LauncherEmpty => {}
            Self::LauncherRecs => {
                state.reveals_recommendations = true;
            }
            Self::LauncherQuery(q) => state.type_text(q),
            Self::Calculator => state.type_text("2 + 2"),
            Self::ClipboardEmpty => {
                state.clipboard_items.clear();
                state.enter_clipboard("");
            }
            Self::FilesEmpty => state.enter_files(""),
            Self::FilesQuery(q) => {
                state.enter_files(q);
            }
            Self::SettingsAppearance | Self::Notes => {
                state.hide();
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScreenshotExpectation {
    pub slug: String,
    pub max_height: Option<f64>,
    pub must_be_compact: bool,
    pub session: Option<LauncherSession>,
}

impl ScreenshotScenario {
    /// Compact-bar stills must never capture a huge dim overlay.
    pub fn expectation(&self) -> ScreenshotExpectation {
        match self {
            Self::LauncherEmpty | Self::ClipboardEmpty | Self::FilesEmpty => {
                ScreenshotExpectation {
                    slug: self.slug(),
                    max_height: Some(LauncherLayout::compact_height()),
                    must_be_compact: true,
                    session: match self {
                        Self::ClipboardEmpty => Some(LauncherSession::Clipboard),
                        Self::FilesEmpty => Some(LauncherSession::Files),
                        _ => Some(LauncherSession::Commands),
                    },
                }
            }
            _ => ScreenshotExpectation {
                slug: self.slug(),
                max_height: None,
                must_be_compact: false,
                session: None,
            },
        }
    }
}

/// Pixel height of a PNG. Used by CI to reject overlay-sized clipboard/files captures.
pub fn png_pixel_height(bytes: &[u8]) -> Option<u32> {
    if bytes.len() < 24 || &bytes[0..8] != b"\x89PNG\r\n\x1a\n" {
        return None;
    }
    Some(u32::from_be_bytes(bytes[20..24].try_into().ok()?))
}

/// Compact stills on a 2x display are ~178px tall. A dim overlay is many hundreds.
pub fn compact_png_is_overlay(png: &[u8]) -> bool {
    match png_pixel_height(png) {
        Some(h) => h > 420,
        None => false,
    }
}

pub fn assert_scenario_layout(scenario: &ScreenshotScenario, state: &LauncherState) {
    let expect = scenario.expectation();
    if expect.must_be_compact {
        assert!(
            matches!(state.content(), Content::SearchOnly),
            "{} must be a compact bar, got {:?}",
            expect.slug,
            state.content()
        );
        assert_eq!(state.panel_height(), LauncherLayout::compact_height());
    }
    if let Some(session) = expect.session {
        assert_eq!(state.session, session);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_scenarios_match_stills() {
        for raw in ["launcher-empty", "clipboard-empty", "files-empty"] {
            let scenario = ScreenshotScenario::parse(raw).unwrap();
            let mut state = LauncherState::default();
            scenario.apply(&mut state);
            assert_scenario_layout(&scenario, &state);
        }
    }

    #[test]
    fn overlay_detector_flags_tall_png_header() {
        let mut png = vec![0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n'];
        png.extend_from_slice(&[0, 0, 0, 13]); // IHDR length
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&800u32.to_be_bytes()); // width
        png.extend_from_slice(&900u32.to_be_bytes()); // height
        assert!(compact_png_is_overlay(&png));
        let mut short = png.clone();
        short[20..24].copy_from_slice(&178u32.to_be_bytes());
        assert!(!compact_png_is_overlay(&short));
    }
}
