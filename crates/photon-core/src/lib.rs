//! Platform-neutral Photon core: launcher geometry, fuzzy ranking, calculator, frecency.

pub mod calculator;
pub mod command;
pub mod frecency;
pub mod fuzzy;
pub mod launcher;
pub mod layout;
pub mod position;
pub mod screenshot;
pub mod settings;
pub mod version;

pub use calculator::{CalculatorDisplayModel, CalculatorEngine, CalculatorResult};
pub use command::{Command, CommandIcon, RankedCommand};
pub use frecency::{FrecencyRecord, FrecencyStore};
pub use fuzzy::FuzzyMatcher;
pub use launcher::{
    KeyEvent, LauncherContent, LauncherModeKind, LauncherSession, LauncherState, Modifiers,
};
pub use layout::{LauncherLayout, LauncherPanelWidth};
pub use position::{
    LauncherPosition, LauncherStoredPosition, PanelOrigin, PanelSize, ScreenVisibleFrame,
};
pub use screenshot::{ScreenshotExpectation, ScreenshotScenario};
pub use settings::{AppAppearance, PhotonSettings};
pub use version::PHOTON_VERSION;
