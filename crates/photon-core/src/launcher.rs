//! Headless launcher session: clipboard compact/expand, files compact empty, mixing.

use crate::calculator::{CalculatorDisplayModel, CalculatorEngine};
use crate::command::Command;
use crate::layout::{Content, LauncherLayout, LauncherPanelWidth};

/// Re-export so callers can name the panel content enum `LauncherContent`.
pub type LauncherContent = Content;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LauncherSession {
    Commands,
    Clipboard,
    Files,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LauncherModeKind {
    None,
    Files,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Modifiers {
    pub command: bool,
    pub shift: bool,
    pub option: bool,
    pub control: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyEvent {
    Character(char),
    Backspace,
    Escape,
    Return,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    ControlN,
    ControlP,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardRow {
    pub id: String,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileRow {
    pub path: String,
    pub display_name: String,
    pub is_folder: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LauncherState {
    pub session: LauncherSession,
    pub query: String,
    pub shows_suggestions: bool,
    pub reveals_recommendations: bool,
    pub clipboard_shows_results: bool,
    pub clipboard_enabled: bool,
    pub clipboard_items: Vec<ClipboardRow>,
    pub clipboard_selected: usize,
    pub file_results: Vec<FileRow>,
    pub file_is_searching: bool,
    pub commands: Vec<Command>,
    pub selected_command: usize,
    pub panel_width: LauncherPanelWidth,
    pub visible: bool,
}

impl Default for LauncherState {
    fn default() -> Self {
        Self {
            session: LauncherSession::Commands,
            query: String::new(),
            shows_suggestions: false,
            reveals_recommendations: false,
            clipboard_shows_results: false,
            clipboard_enabled: true,
            clipboard_items: Vec::new(),
            clipboard_selected: 0,
            file_results: Vec::new(),
            file_is_searching: false,
            commands: Vec::new(),
            selected_command: 0,
            panel_width: LauncherPanelWidth::Regular,
            visible: false,
        }
    }
}

impl LauncherState {
    pub fn placeholder(&self) -> &'static str {
        match self.session {
            LauncherSession::Clipboard => "Search clipboard history…",
            LauncherSession::Files => "Search files",
            LauncherSession::Commands => "Search apps, files, notes and more…",
        }
    }

    pub fn content(&self) -> LauncherContent {
        match self.session {
            LauncherSession::Clipboard => self.clipboard_content(),
            LauncherSession::Files => {
                if self.file_results.is_empty() {
                    Content::SearchOnly
                } else {
                    Content::Rows {
                        count: self
                            .file_results
                            .len()
                            .min(LauncherLayout::MAX_VISIBLE_ROWS),
                        shows_calculator_hero: false,
                    }
                }
            }
            LauncherSession::Commands => {
                if self.query.is_empty() && !self.shows_suggestions && !self.reveals_recommendations
                {
                    Content::SearchOnly
                } else if let Some(calc) = self.calculator_hero() {
                    Content::Rows {
                        count: 1.max(self.visible_command_count()),
                        shows_calculator_hero: true,
                    }
                    .and_ignore(calc)
                } else {
                    Content::Rows {
                        count: self.visible_command_count(),
                        shows_calculator_hero: false,
                    }
                }
            }
        }
    }

    fn clipboard_content(&self) -> LauncherContent {
        let shows_compact_empty_row =
            !self.clipboard_enabled || (!self.clipboard_items.is_empty() && !self.query.is_empty());
        if !self.clipboard_shows_results && self.query.is_empty() && !shows_compact_empty_row {
            return Content::SearchOnly;
        }
        if !self.clipboard_filtered().is_empty() {
            return Content::Rows {
                count: self.clipboard_filtered().len(),
                shows_calculator_hero: false,
            };
        }
        if shows_compact_empty_row {
            Content::Rows {
                count: 1,
                shows_calculator_hero: false,
            }
        } else {
            Content::SearchOnly
        }
    }

    pub fn panel_height(&self) -> f64 {
        LauncherLayout::height_for(self.content())
    }

    pub fn is_compact(&self) -> bool {
        matches!(self.content(), Content::SearchOnly)
    }

    pub fn calculator_hero(&self) -> Option<CalculatorDisplayModel> {
        if self.session != LauncherSession::Commands {
            return None;
        }
        CalculatorEngine::evaluate(&self.query)
            .map(|r| CalculatorDisplayModel::from_result(&r, "photon.calculator"))
    }

    pub fn clipboard_filtered(&self) -> Vec<ClipboardRow> {
        let q = self.query.to_lowercase();
        if q.is_empty() {
            return self.clipboard_items.clone();
        }
        self.clipboard_items
            .iter()
            .filter(|item| item.title.to_lowercase().contains(&q))
            .cloned()
            .collect()
    }

    fn visible_command_count(&self) -> usize {
        if self.calculator_hero().is_some() {
            1
        } else {
            self.commands.len()
        }
    }

    pub fn show(&mut self) {
        self.visible = true;
        self.reset_transient();
    }

    pub fn hide(&mut self) {
        self.reset_transient();
        self.visible = false;
    }

    /// Collapse clipboard/mode chrome before the window is ordered out so the next
    /// open cannot inherit a tall panel around a compact root.
    pub fn reset_transient(&mut self) {
        self.clipboard_shows_results = false;
        self.reveals_recommendations = false;
        self.file_is_searching = false;
        self.file_results.clear();
        if self.session != LauncherSession::Commands {
            self.session = LauncherSession::Commands;
        }
        self.query.clear();
    }

    pub fn enter_clipboard(&mut self, initial_query: &str) {
        self.clipboard_shows_results = !initial_query.is_empty();
        self.session = LauncherSession::Clipboard;
        self.query = initial_query.to_string();
        self.clipboard_selected = 0;
        self.file_results.clear();
        self.file_is_searching = false;
        self.reveals_recommendations = false;
    }

    pub fn exit_clipboard(&mut self) {
        if self.session != LauncherSession::Clipboard {
            return;
        }
        self.clipboard_shows_results = false;
        self.session = LauncherSession::Commands;
        self.query.clear();
    }

    pub fn enter_files(&mut self, initial_query: &str) {
        self.session = LauncherSession::Files;
        self.query = initial_query.to_string();
        self.clipboard_shows_results = false;
        self.file_is_searching = false;
        if initial_query.trim().is_empty() {
            self.file_results.clear();
        }
    }

    pub fn set_file_results(&mut self, rows: Vec<FileRow>) {
        self.file_is_searching = false;
        self.file_results = rows;
    }

    pub fn type_text(&mut self, text: &str) {
        for ch in text.chars() {
            self.handle_key(KeyEvent::Character(ch), Modifiers::default());
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent, modifiers: Modifiers) -> bool {
        match self.session {
            LauncherSession::Clipboard => self.handle_clipboard_key(key, modifiers),
            LauncherSession::Files => self.handle_files_key(key, modifiers),
            LauncherSession::Commands => self.handle_commands_key(key, modifiers),
        }
    }

    fn handle_commands_key(&mut self, key: KeyEvent, _modifiers: Modifiers) -> bool {
        match key {
            KeyEvent::Character(ch) => {
                self.query.push(ch);
                self.try_enter_mode_from_query();
                true
            }
            KeyEvent::Backspace => {
                self.query.pop();
                if self.query.is_empty() && !self.shows_suggestions {
                    self.reveals_recommendations = false;
                    self.commands.clear();
                }
                true
            }
            KeyEvent::Escape => {
                self.hide();
                true
            }
            KeyEvent::Down => {
                if self.query.is_empty() && self.commands.is_empty() {
                    self.reveals_recommendations = true;
                    return true;
                }
                if !self.commands.is_empty() {
                    self.selected_command = (self.selected_command + 1) % self.commands.len();
                }
                true
            }
            KeyEvent::Up => {
                if !self.commands.is_empty() {
                    self.selected_command = if self.selected_command == 0 {
                        self.commands.len() - 1
                    } else {
                        self.selected_command - 1
                    };
                }
                true
            }
            _ => false,
        }
    }

    fn try_enter_mode_from_query(&mut self) {
        let lowered = self.query.to_lowercase();
        if let Some(rest) = lowered.strip_prefix("cb ") {
            let rest = rest.to_string();
            self.enter_clipboard(&rest);
            return;
        }
        if lowered == "cb" {
            return;
        }
        if let Some(rest) = lowered.strip_prefix("f ") {
            let rest = rest.to_string();
            self.enter_files(&rest);
            return;
        }
        if lowered.starts_with('/') {
            let rest = self.query[1..].to_string();
            self.enter_files(&rest);
        }
    }

    fn handle_clipboard_key(&mut self, key: KeyEvent, modifiers: Modifiers) -> bool {
        if matches!(key, KeyEvent::Escape) {
            self.exit_clipboard();
            return true;
        }
        if matches!(key, KeyEvent::Backspace) && self.query.is_empty() && !modifiers.command {
            self.exit_clipboard();
            return true;
        }
        if let Some(delta) = clipboard_list_delta(key, modifiers) {
            self.move_clipboard_selection(delta);
            return true;
        }
        match key {
            KeyEvent::Home | KeyEvent::End => {
                let filtered = self.clipboard_filtered();
                if !self.clipboard_shows_results && !filtered.is_empty() {
                    self.move_clipboard_selection(1);
                }
                let filtered = self.clipboard_filtered();
                if filtered.is_empty() {
                    return true;
                }
                self.clipboard_selected = if matches!(key, KeyEvent::Home) {
                    0
                } else {
                    filtered.len() - 1
                };
                true
            }
            KeyEvent::Character(ch) => {
                self.query.push(ch);
                if !self.query.is_empty() {
                    self.clipboard_shows_results = true;
                }
                self.clipboard_selected = 0;
                true
            }
            KeyEvent::Backspace => {
                self.query.pop();
                true
            }
            _ => false,
        }
    }

    fn move_clipboard_selection(&mut self, delta: i32) {
        let filtered = self.clipboard_filtered();
        if filtered.is_empty() {
            return;
        }
        if !self.clipboard_shows_results {
            self.clipboard_shows_results = true;
            self.clipboard_selected = if delta < 0 { filtered.len() - 1 } else { 0 };
            return;
        }
        let count = filtered.len() as i32;
        let index = self.clipboard_selected as i32;
        self.clipboard_selected = ((index + delta).rem_euclid(count)) as usize;
    }

    fn handle_files_key(&mut self, key: KeyEvent, _modifiers: Modifiers) -> bool {
        match key {
            KeyEvent::Escape => {
                self.session = LauncherSession::Commands;
                self.query.clear();
                self.file_results.clear();
                self.file_is_searching = false;
                true
            }
            KeyEvent::Backspace if self.query.is_empty() => {
                self.session = LauncherSession::Commands;
                self.file_results.clear();
                true
            }
            KeyEvent::Character(ch) => {
                self.query.push(ch);
                // Searching never expands the empty panel; results do.
                self.file_is_searching = self.file_results.is_empty();
                true
            }
            KeyEvent::Backspace => {
                self.query.pop();
                if self.query.is_empty() {
                    self.file_results.clear();
                    self.file_is_searching = false;
                }
                true
            }
            _ => false,
        }
    }
}

fn clipboard_list_delta(key: KeyEvent, modifiers: Modifiers) -> Option<i32> {
    if modifiers.command || modifiers.option {
        return None;
    }
    match key {
        KeyEvent::Down | KeyEvent::ControlN => Some(1),
        KeyEvent::Up | KeyEvent::ControlP => Some(-1),
        KeyEvent::PageDown => Some(LauncherLayout::MAX_VISIBLE_ROWS as i32),
        KeyEvent::PageUp => Some(-(LauncherLayout::MAX_VISIBLE_ROWS as i32)),
        _ => None,
    }
}

trait IgnoreCalc {
    fn and_ignore(self, _calc: CalculatorDisplayModel) -> Self;
}

impl IgnoreCalc for Content {
    fn and_ignore(self, _calc: CalculatorDisplayModel) -> Self {
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seeded_clipboard() -> LauncherState {
        let mut state = LauncherState::default();
        state.clipboard_items = vec![
            ClipboardRow {
                id: "1".into(),
                title: "first item".into(),
            },
            ClipboardRow {
                id: "2".into(),
                title: "second item".into(),
            },
            ClipboardRow {
                id: "3".into(),
                title: "ember notes".into(),
            },
        ];
        state
    }

    #[test]
    fn clipboard_opens_compact_even_with_history() {
        let mut state = seeded_clipboard();
        state.enter_clipboard("");
        assert!(state.is_compact(), "Cmd+Shift+V must open the compact bar");
        assert_eq!(state.panel_height(), LauncherLayout::compact_height());
        assert!(!state.clipboard_shows_results);
    }

    #[test]
    fn down_expands_then_up_down_cycle() {
        let mut state = seeded_clipboard();
        state.enter_clipboard("");
        state.handle_key(KeyEvent::Down, Modifiers::default());
        assert!(!state.is_compact());
        assert_eq!(state.clipboard_selected, 0);
        state.handle_key(KeyEvent::Down, Modifiers::default());
        assert_eq!(state.clipboard_selected, 1);
        state.handle_key(KeyEvent::Up, Modifiers::default());
        assert_eq!(state.clipboard_selected, 0);
        state.handle_key(KeyEvent::Up, Modifiers::default());
        assert_eq!(state.clipboard_selected, 2);
    }

    #[test]
    fn typing_filters_and_arrows_still_move() {
        let mut state = seeded_clipboard();
        state.enter_clipboard("");
        state.type_text("ember");
        assert!(state.clipboard_shows_results);
        assert_eq!(state.clipboard_filtered().len(), 1);
        state.handle_key(KeyEvent::Down, Modifiers::default());
        assert_eq!(state.clipboard_selected, 0);
        assert_eq!(state.clipboard_filtered()[0].title, "ember notes");
    }

    #[test]
    fn dismiss_and_reopen_restores_compact_bar() {
        let mut state = seeded_clipboard();
        state.show();
        state.enter_clipboard("");
        state.handle_key(KeyEvent::Down, Modifiers::default());
        assert!(!state.is_compact());
        state.hide();
        assert!(!state.visible);
        assert!(state.is_compact());
        state.show();
        state.enter_clipboard("");
        assert!(
            state.is_compact(),
            "reopen after dismiss must not keep a huge overlay"
        );
        assert_eq!(state.panel_height(), LauncherLayout::compact_height());
        assert_eq!(state.session, LauncherSession::Clipboard);
    }

    #[test]
    fn opening_clipboard_from_main_launcher_is_compact() {
        let mut state = seeded_clipboard();
        state.show();
        state.enter_clipboard("");
        assert!(state.is_compact());
        state.hide();
        state.show();
        state.query = "cb ".into();
        state.try_enter_mode_from_query();
        assert_eq!(state.session, LauncherSession::Clipboard);
        assert!(state.is_compact());
    }

    #[test]
    fn empty_files_panel_stays_compact_while_searching() {
        let mut state = LauncherState::default();
        state.enter_files("");
        assert!(state.is_compact());
        state.type_text("ica");
        assert!(
            state.is_compact(),
            "Searching must not expand into a full overlay"
        );
        assert!(state.file_is_searching);
        state.set_file_results(vec![FileRow {
            path: "/Users/ryan/Documents/readme.md".into(),
            display_name: "readme.md".into(),
            is_folder: false,
        }]);
        assert!(!state.is_compact());
        assert!(!state.file_is_searching);
    }

    #[test]
    fn calculator_query_uses_hero_height() {
        let mut state = LauncherState::default();
        state.type_text("2 + 2");
        let hero = state.calculator_hero().unwrap();
        assert_eq!(hero.value, "4");
        assert!(matches!(
            state.content(),
            Content::Rows {
                shows_calculator_hero: true,
                ..
            }
        ));
    }

    #[test]
    fn down_on_empty_bar_reveals_recommendations() {
        let mut state = LauncherState::default();
        state.show();
        assert!(state.is_compact());
        state.handle_key(KeyEvent::Down, Modifiers::default());
        assert!(state.reveals_recommendations);
        assert!(!state.is_compact() || state.commands.is_empty());
    }
}
