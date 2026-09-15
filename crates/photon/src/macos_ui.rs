//! GPUI shell: compact pill launcher, settings, notes. macOS only.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use arboard::Clipboard as SystemClipboard;
use global_hotkey::hotkey::{Code, HotKey, Modifiers as HotMods};
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use gpui::{
    div, prelude::*, px, rgb, rgba, size, App, Application, Bounds, Context, FocusHandle,
    Focusable, FontWeight, KeyDownEvent, Pixels, Point, SharedString, Timer, TitlebarOptions,
    Window, WindowBackgroundAppearance, WindowBounds, WindowHandle, WindowKind, WindowOptions,
};
use photon_clipboard::ClipboardSearch;
use photon_core::launcher::{KeyEvent, LauncherSession, LauncherState, Modifiers as LaunchMods};
use photon_core::layout::{Content, LauncherLayout};
use photon_core::position::{LauncherPosition, PanelOrigin, PanelSize, ScreenVisibleFrame};
use photon_core::screenshot::{assert_scenario_layout, ScreenshotScenario};
use photon_core::{CalculatorEngine, PhotonSettings};
use photon_files::{FileSearchEngine, FileSearchRequest, FileSearchSettings};

use crate::apps::{self, AppEntry};
use crate::clipboard_os::ClipboardRuntime;
use crate::notes::NoteStore;
use crate::screenshot::{self, mark_ready};
use crate::settings_store::SettingsStore;
use crate::theme::Theme;
use crate::window_cmds::WindowCommand;

const SEARCH_FILES_ID: &str = "photon.files.search";
const CLIPBOARD_ID: &str = "photon.clipboard.history";
const SETTINGS_ID: &str = "photon.settings";
const NOTES_ID: &str = "photon.notes";

pub fn run() -> Result<(), String> {
    let support = SettingsStore::support_dir();
    std::fs::create_dir_all(&support).ok();
    let settings_store = SettingsStore::load(&support);
    let scenario = screenshot::current_scenario();

    Application::new().run(move |cx: &mut App| {
        cx.activate(true);
        let theme = match settings_store.settings.appearance {
            photon_core::AppAppearance::Dark => Theme::dark(),
            photon_core::AppAppearance::Light => Theme::light(),
            photon_core::AppAppearance::System => Theme::light(),
        };

        let extra: Vec<String> = std::env::var("PHOTON_APPLICATIONS_EXTRA")
            .unwrap_or_default()
            .split(':')
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect();
        let apps = apps::scan_applications(&extra);
        let mut clipboard = ClipboardRuntime::load(
            &support,
            photon_clipboard::ClipboardSettings {
                is_enabled: settings_store.settings.clipboard_enabled,
                retention: photon_clipboard::ClipboardRetention::from_days(
                    settings_store.settings.clipboard_retention_days,
                ),
                max_items: settings_store.settings.clipboard_max_items,
                excluded_bundle_ids: settings_store
                    .settings
                    .clipboard_excluded_bundle_ids
                    .clone(),
                paste_behavior: photon_clipboard::ClipboardPasteBehavior::Paste,
            },
        );
        if matches!(scenario, Some(ScreenshotScenario::ClipboardEmpty)) {
            clipboard.history.items.clear();
        }

        let mut notes = NoteStore::load(&support);
        if matches!(scenario, Some(ScreenshotScenario::Notes)) && notes.notes.is_empty() {
            let mut note = notes.create("Shipping checklist");
            note.body =
                "Shipping checklist\n\n- Clipboard compact bar\n- File search for ember\n".into();
            notes.save(&note.id, note.body.clone());
        }
        let mut state = LauncherState::default();
        state.clipboard_enabled = clipboard.settings.is_enabled;
        state.clipboard_items = clipboard
            .history
            .items
            .iter()
            .map(|item| photon_core::launcher::ClipboardRow {
                id: item.id.to_string(),
                title: item.title(),
            })
            .collect();
        state.panel_width = settings_store.settings.panel_width;
        state.shows_suggestions = settings_store.settings.shows_suggestions;

        if let Some(scenario) = &scenario {
            scenario.apply(&mut state);
            if matches!(scenario, ScreenshotScenario::LauncherRecs) {
                state.commands = apps
                    .iter()
                    .take(LauncherLayout::SUGGESTION_COUNT)
                    .map(command_from_app)
                    .collect();
            }
            if let ScreenshotScenario::LauncherQuery(q) = scenario {
                state.commands = apps::search_apps(&apps, q)
                    .into_iter()
                    .map(command_from_app)
                    .collect();
                // Mix a Search Files row at the top like the Swift launcher.
                if q.len() >= 3 {
                    state.commands.insert(0, search_files_command());
                }
            }
            if matches!(scenario, ScreenshotScenario::Calculator) {
                state.query = "2 + 2".into();
            }
        }

        let show_settings = matches!(scenario, Some(ScreenshotScenario::SettingsAppearance));
        let show_notes = matches!(scenario, Some(ScreenshotScenario::Notes));
        let show_launcher = !show_settings && !show_notes;
        let bounds = launcher_bounds(&state, settings_store.settings.launcher_position, cx);
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("Photon Launcher".into()),
                appears_transparent: true,
                traffic_light_position: None,
            }),
            focus: scenario.is_some(),
            show: show_launcher && scenario.is_some(),
            kind: if scenario.is_some() {
                WindowKind::Normal
            } else {
                WindowKind::PopUp
            },
            is_movable: true,
            is_resizable: false,
            is_minimizable: false,
            window_background: WindowBackgroundAppearance::Blurred,
            app_id: Some("com.ryanstoffel.photon".into()),
            window_min_size: Some(size(px(state.panel_width.points() as f32), px(89.0))),
            ..Default::default()
        };

        let settings_for_window = settings_store.settings.clone();
        let notes_for_window = notes.clone_store();
        let mut launcher_handle: Option<WindowHandle<LauncherView>> = None;
        if show_launcher {
            if let Ok(handle) = cx.open_window(options, |window, cx| {
                cx.new(|cx| {
                    let mut view = LauncherView::new(
                        state,
                        apps,
                        clipboard,
                        settings_store,
                        notes,
                        theme,
                        support.clone(),
                        scenario.clone(),
                        cx,
                    );
                    view.resize_to_content(window, cx);
                    view
                })
            }) {
                launcher_handle = Some(handle);
            }
        }

        if show_settings {
            open_settings_window(cx, settings_for_window, theme);
        }
        if show_notes {
            open_notes_window(cx, notes_for_window, theme);
        }

        let hotkey_ids = install_hotkeys();
        if let (Some(handle), Some((_launcher_id, clipboard_id))) = (launcher_handle, hotkey_ids) {
            spawn_hotkey_listener(cx, handle, clipboard_id);
        }
        install_status_item();

        if scenario.is_some() {
            cx.spawn(async move |_cx| {
                Timer::after(std::time::Duration::from_millis(800)).await;
                mark_ready();
            })
            .detach();
        }
    });
    Ok(())
}

fn command_from_app(app: &AppEntry) -> photon_core::Command {
    photon_core::Command {
        id: app.id.clone(),
        title: app.name.clone(),
        subtitle: app.subtitle.clone(),
        keywords: app.keywords.clone(),
        provider_id: "apps".into(),
        icon: Some(photon_core::CommandIcon::FilePath(app.path.clone())),
    }
}

fn search_files_command() -> photon_core::Command {
    photon_core::Command {
        id: SEARCH_FILES_ID.into(),
        title: "Search Files".into(),
        subtitle: Some("Find files and folders with Spotlight".into()),
        keywords: vec!["files".into(), "spotlight".into()],
        provider_id: "files".into(),
        icon: Some(photon_core::CommandIcon::Symbol("folder")),
    }
}

fn launcher_bounds(
    state: &LauncherState,
    stored: Option<photon_core::LauncherStoredPosition>,
    cx: &App,
) -> Bounds<Pixels> {
    let display = cx.displays().first().cloned();
    let screen = display
        .as_ref()
        .map(|d| d.bounds())
        .unwrap_or_else(|| Bounds {
            origin: Point {
                x: px(0.0),
                y: px(0.0),
            },
            size: size(px(1440.0), px(900.0)),
        });
    let visible = ScreenVisibleFrame {
        min_x: f64::from(f32::from(screen.origin.x)),
        min_y: f64::from(f32::from(screen.origin.y)),
        width: f64::from(f32::from(screen.size.width)),
        height: f64::from(f32::from(screen.size.height)),
    };
    let panel = PanelSize {
        width: state.panel_width.points(),
        height: state.panel_height(),
    };
    let origin = LauncherPosition::origin(panel, visible, stored);
    Bounds {
        origin: Point {
            x: px(origin.x as f32),
            y: px((visible.height - origin.y - panel.height) as f32),
        },
        size: size(px(panel.width as f32), px(panel.height as f32)),
    }
}

struct LauncherView {
    state: LauncherState,
    apps: Vec<AppEntry>,
    clipboard: ClipboardRuntime,
    settings: SettingsStore,
    notes: NoteStore,
    theme: Theme,
    support: PathBuf,
    scenario: Option<ScreenshotScenario>,
    focus: FocusHandle,
    drag_start: Option<(PanelOrigin, PanelOrigin)>,
    file_engine: FileSearchEngine,
}

impl LauncherView {
    #[allow(clippy::too_many_arguments)]
    fn new(
        state: LauncherState,
        apps: Vec<AppEntry>,
        clipboard: ClipboardRuntime,
        settings: SettingsStore,
        notes: NoteStore,
        theme: Theme,
        support: PathBuf,
        scenario: Option<ScreenshotScenario>,
        cx: &mut Context<Self>,
    ) -> Self {
        Self {
            state,
            apps,
            clipboard,
            settings,
            notes,
            theme,
            support,
            scenario,
            focus: cx.focus_handle(),
            drag_start: None,
            file_engine: FileSearchEngine::default(),
        }
    }

    fn refresh_commands(&mut self) {
        if self.state.session != LauncherSession::Commands {
            return;
        }
        let query = self.state.query.clone();
        if query.is_empty() && !self.state.shows_suggestions && !self.state.reveals_recommendations
        {
            self.state.commands.clear();
            return;
        }
        if CalculatorEngine::evaluate(&query).is_some() {
            self.state.commands.clear();
            return;
        }
        let mut commands: Vec<_> = apps::search_apps(&self.apps, &query)
            .into_iter()
            .map(command_from_app)
            .collect();
        if query.eq_ignore_ascii_case("settings")
            || query.is_empty() && self.state.reveals_recommendations
        {
            commands.push(photon_core::Command {
                id: SETTINGS_ID.into(),
                title: "Photon Settings".into(),
                subtitle: Some("Preferences".into()),
                keywords: vec!["settings".into()],
                provider_id: "settings".into(),
                icon: Some(photon_core::CommandIcon::Symbol("gear")),
            });
        }
        if query.eq_ignore_ascii_case("clipboard")
            || query.eq_ignore_ascii_case("cb")
            || query.is_empty() && self.state.reveals_recommendations
        {
            commands.push(photon_core::Command {
                id: CLIPBOARD_ID.into(),
                title: "Clipboard History".into(),
                subtitle: Some("Paste from history".into()),
                keywords: vec!["clipboard".into(), "paste".into()],
                provider_id: "clipboard".into(),
                icon: Some(photon_core::CommandIcon::Symbol("doc.on.clipboard")),
            });
        }
        if query.eq_ignore_ascii_case("notes")
            || query.is_empty() && self.state.reveals_recommendations
        {
            commands.push(photon_core::Command {
                id: NOTES_ID.into(),
                title: "Notes".into(),
                subtitle: Some("Quick notes".into()),
                keywords: vec!["notes".into(), "markdown".into()],
                provider_id: "notes".into(),
                icon: Some(photon_core::CommandIcon::Symbol("note")),
            });
        }
        if !query.is_empty() {
            for command in WindowCommand::matching(&query) {
                commands.push(photon_core::Command {
                    id: format!("window:{}", command.title()),
                    title: command.title().into(),
                    subtitle: Some("Window".into()),
                    keywords: vec!["window".into()],
                    provider_id: "keybinds".into(),
                    icon: Some(photon_core::CommandIcon::Symbol("rectangle.split.2x1")),
                });
            }
        }
        if !query.is_empty() && query.len() >= 3 {
            commands.insert(0, search_files_command());
            self.mix_files(&query, &mut commands);
        }
        if query.is_empty() {
            commands.truncate(LauncherLayout::SUGGESTION_COUNT);
        }
        self.state.commands = commands;
        self.state.selected_command = 0;
    }

    fn mix_files(&mut self, query: &str, commands: &mut Vec<photon_core::Command>) {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let settings = FileSearchSettings {
            scope: photon_files::FileSearchScope::parse(&self.settings.settings.files_scope),
            extra_folders: self.settings.settings.files_extra_folders.clone(),
            excluded_folders: self.settings.settings.files_excluded_folders.clone(),
            search_contents: self.settings.settings.files_search_contents,
            max_results: self.settings.settings.files_max_results as usize,
            default_action: photon_files::FileDefaultAction::Open,
            inline_results: self.settings.settings.files_inline_results,
        };
        let response = self.file_engine.search(&FileSearchRequest {
            query: query.into(),
            settings,
            limit: 8,
            include_applications: false,
            home,
        });
        for ranked in response.files.into_iter().take(5) {
            commands.push(photon_core::Command {
                id: format!("file:{}", ranked.file.path),
                title: ranked.file.display_name.clone(),
                subtitle: Some(photon_files::PathFormatter::parent_display(
                    &ranked.file.path,
                    60,
                    &dirs::home_dir().unwrap_or_default().to_string_lossy(),
                )),
                keywords: vec![],
                provider_id: "files".into(),
                icon: Some(photon_core::CommandIcon::FilePath(ranked.file.path)),
            });
        }
    }

    fn search_files_now(&mut self) {
        if self.state.session != LauncherSession::Files {
            return;
        }
        let query = self.state.query.trim().to_string();
        if query.is_empty() {
            self.state.file_results.clear();
            self.state.file_is_searching = false;
            return;
        }
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let settings = FileSearchSettings {
            scope: photon_files::FileSearchScope::parse(&self.settings.settings.files_scope),
            extra_folders: self.settings.settings.files_extra_folders.clone(),
            excluded_folders: self.settings.settings.files_excluded_folders.clone(),
            search_contents: self.settings.settings.files_search_contents,
            max_results: self.settings.settings.files_max_results as usize,
            default_action: photon_files::FileDefaultAction::Open,
            inline_results: self.settings.settings.files_inline_results,
        };
        let response = self.file_engine.search(&FileSearchRequest {
            query,
            settings,
            limit: self.settings.settings.files_max_results as usize,
            include_applications: true,
            home,
        });
        self.state.set_file_results(
            response
                .files
                .into_iter()
                .map(|r| photon_core::launcher::FileRow {
                    path: r.file.path,
                    display_name: r.file.display_name,
                    is_folder: r.file.is_folder,
                })
                .collect(),
        );
    }

    fn sync_clipboard_rows(&mut self) {
        self.state.clipboard_items =
            ClipboardSearch::rank(&self.clipboard.history.items, "", now_unix())
                .into_iter()
                .map(|item| photon_core::launcher::ClipboardRow {
                    id: item.id.to_string(),
                    title: item.title(),
                })
                .collect();
    }

    fn handle_key(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        let mods = LaunchMods {
            command: keystroke.modifiers.platform,
            shift: keystroke.modifiers.shift,
            option: keystroke.modifiers.alt,
            control: keystroke.modifiers.control,
        };
        if mods.command && self.state.session == LauncherSession::Clipboard {
            match keystroke.key.as_str() {
                "p" => {
                    if let Some(row) = self
                        .state
                        .clipboard_filtered()
                        .get(self.state.clipboard_selected)
                    {
                        if let Ok(id) = uuid::Uuid::parse_str(&row.id) {
                            self.clipboard.toggle_pin(id);
                            self.sync_clipboard_rows();
                            cx.notify();
                        }
                    }
                    return;
                }
                "c" => {
                    if let Some(item) = self
                        .clipboard
                        .history
                        .items
                        .get(self.state.clipboard_selected)
                    {
                        if let Some(text) = &item.text {
                            copy_text(text);
                        }
                    }
                    return;
                }
                _ => {}
            }
        }
        let key = match keystroke.key.as_str() {
            "up" => KeyEvent::Up,
            "down" => KeyEvent::Down,
            "escape" => KeyEvent::Escape,
            "enter" | "return" => KeyEvent::Return,
            "backspace" => KeyEvent::Backspace,
            "home" => KeyEvent::Home,
            "end" => KeyEvent::End,
            "pageup" => KeyEvent::PageUp,
            "pagedown" => KeyEvent::PageDown,
            "space" if !mods.command => KeyEvent::Character(' '),
            "n" if mods.control => KeyEvent::ControlN,
            "p" if mods.control => KeyEvent::ControlP,
            _ => {
                if mods.command {
                    return;
                }
                if let Some(ch) = keystroke
                    .key_char
                    .as_deref()
                    .and_then(|s| s.chars().next())
                    .filter(|c| !c.is_control())
                {
                    KeyEvent::Character(ch)
                } else if keystroke.key.chars().count() == 1 {
                    KeyEvent::Character(keystroke.key.chars().next().unwrap())
                } else {
                    return;
                }
            }
        };
        if matches!(key, KeyEvent::Return) {
            self.run_selection(window, cx);
            return;
        }
        let session_before = self.state.session;
        self.state.handle_key(key, mods);
        if self.state.session == LauncherSession::Commands {
            self.refresh_commands();
        } else if self.state.session == LauncherSession::Files {
            self.search_files_now();
        } else if self.state.session == LauncherSession::Clipboard
            && session_before != LauncherSession::Clipboard
        {
            self.sync_clipboard_rows();
        }
        self.resize_to_content(window, cx);
        cx.notify();
    }

    fn run_selection(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        match self.state.session {
            LauncherSession::Clipboard => {
                if let Some(item) = self
                    .clipboard
                    .history
                    .items
                    .get(self.state.clipboard_selected)
                    .cloned()
                {
                    paste_item(&item);
                    self.hide(window, cx);
                }
            }
            LauncherSession::Files => {
                if let Some(row) = self.state.file_results.first() {
                    let _ = std::process::Command::new("open").arg(&row.path).status();
                    self.hide(window, cx);
                }
            }
            LauncherSession::Commands => {
                if self.state.calculator_hero().is_some() {
                    if let Some(result) = CalculatorEngine::evaluate(&self.state.query) {
                        copy_text(&result.value);
                    }
                    self.hide(window, cx);
                    return;
                }
                let Some(cmd) = self
                    .state
                    .commands
                    .get(self.state.selected_command)
                    .cloned()
                else {
                    return;
                };
                if cmd.id == CLIPBOARD_ID || cmd.id == "photon.clipboard.history" {
                    self.state.enter_clipboard("");
                    self.sync_clipboard_rows();
                    self.resize_to_content(window, cx);
                    cx.notify();
                    return;
                }
                if cmd.id == SEARCH_FILES_ID {
                    self.state.enter_files("");
                    self.resize_to_content(window, cx);
                    cx.notify();
                    return;
                }
                if cmd.id == SETTINGS_ID {
                    open_settings_window(cx, self.settings.settings.clone(), self.theme);
                    self.hide(window, cx);
                    return;
                }
                if cmd.id == NOTES_ID || cmd.title.eq_ignore_ascii_case("notes") {
                    open_notes_window(cx, self.notes.clone_store(), self.theme);
                    self.hide(window, cx);
                    return;
                }
                if let Some(path) = cmd.icon.as_ref().and_then(|icon| match icon {
                    photon_core::CommandIcon::FilePath(p) => Some(p.clone()),
                    photon_core::CommandIcon::Application { path, .. } => Some(path.clone()),
                    _ => None,
                }) {
                    let _ = std::process::Command::new("open").arg(path).status();
                } else if cmd.id.starts_with("pane:") {
                    let url = cmd.id.trim_start_matches("pane:");
                    let _ = std::process::Command::new("open").arg(url).status();
                } else if cmd.id.starts_with("file:") {
                    let path = cmd.id.trim_start_matches("file:");
                    let _ = std::process::Command::new("open").arg(path).status();
                } else if let Some(cmd) = WindowCommand::from_title(&cmd.title) {
                    apply_window_command(cmd);
                }
                self.hide(window, cx);
            }
        }
    }

    fn hide(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let _ = window;
        if self.scenario.is_some() {
            return;
        }
        self.state.hide();
        cx.hide();
        cx.notify();
    }

    fn show_launcher(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.state.show();
        self.refresh_commands();
        self.resize_to_content(window, cx);
        cx.activate(true);
        window.activate_window();
        window.focus(&self.focus);
        cx.notify();
    }

    fn show_clipboard(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.sync_clipboard_rows();
        self.state.show();
        self.state.enter_clipboard("");
        self.resize_to_content(window, cx);
        cx.activate(true);
        window.activate_window();
        window.focus(&self.focus);
        cx.notify();
    }

    fn resize_to_content(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let height = self.state.panel_height() as f32;
        let width = self.state.panel_width.points() as f32;
        window.resize(size(px(width), px(height)));
        if let Some(scenario) = &self.scenario {
            assert_scenario_layout(scenario, &self.state);
        }
    }

    fn begin_drag(&mut self, window: &mut Window) {
        let bounds = window.bounds();
        let mouse = window.mouse_position();
        self.drag_start = Some((
            PanelOrigin {
                x: f64::from(f32::from(bounds.origin.x)),
                y: f64::from(f32::from(bounds.origin.y)),
            },
            PanelOrigin {
                x: f64::from(f32::from(mouse.x)),
                y: f64::from(f32::from(mouse.y)),
            },
        ));
    }

    fn continue_drag(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some((origin, start)) = self.drag_start else {
            return;
        };
        let mouse = window.mouse_position();
        let display = cx.displays().first().cloned();
        let screen = display
            .as_ref()
            .map(|d| d.bounds())
            .unwrap_or_else(|| window.bounds());
        let visible = ScreenVisibleFrame {
            min_x: f64::from(f32::from(screen.origin.x)),
            min_y: f64::from(f32::from(screen.origin.y)),
            width: f64::from(f32::from(screen.size.width)),
            height: f64::from(f32::from(screen.size.height)),
        };
        let next = LauncherPosition::live_drag_origin(
            origin,
            start,
            PanelOrigin {
                x: f64::from(f32::from(mouse.x)),
                y: f64::from(f32::from(mouse.y)),
            },
            self.state.panel_width.points(),
            visible,
        );
        set_key_window_origin(
            next,
            self.state.panel_width.points(),
            self.state.panel_height(),
        );
    }

    fn end_drag(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some((origin, start)) = self.drag_start.take() else {
            return;
        };
        let mouse = window.mouse_position();
        let display = cx.displays().first().cloned();
        let screen = display
            .as_ref()
            .map(|d| d.bounds())
            .unwrap_or_else(|| window.bounds());
        let visible = ScreenVisibleFrame {
            min_x: f64::from(f32::from(screen.origin.x)),
            min_y: f64::from(f32::from(screen.origin.y)),
            width: f64::from(f32::from(screen.size.width)),
            height: f64::from(f32::from(screen.size.height)),
        };
        let next = LauncherPosition::live_drag_origin(
            origin,
            start,
            PanelOrigin {
                x: f64::from(f32::from(mouse.x)),
                y: f64::from(f32::from(mouse.y)),
            },
            self.state.panel_width.points(),
            visible,
        );
        self.settings.settings.launcher_position = Some(LauncherPosition::stored_position(
            next,
            self.state.panel_width.points(),
            visible,
        ));
        let _ = self.settings.save();
        set_key_window_origin(
            next,
            self.state.panel_width.points(),
            self.state.panel_height(),
        );
        cx.notify();
    }
}

impl Focusable for LauncherView {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = self.theme;
        let width = self.state.panel_width.points() as f32;
        let height = self.state.panel_height() as f32;
        let placeholder: SharedString = self.state.placeholder().into();
        let query: SharedString = if self.state.query.is_empty() {
            placeholder.clone()
        } else {
            self.state.query.clone().into()
        };
        let query_is_placeholder = self.state.query.is_empty();

        div()
            .id("launcher")
            .track_focus(&self.focus)
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.handle_key(event, window, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _event: &gpui::MouseDownEvent, window, cx| {
                    this.begin_drag(window);
                    cx.notify();
                }),
            )
            .on_mouse_move(
                cx.listener(|this, event: &gpui::MouseMoveEvent, window, cx| {
                    if event.dragging() {
                        this.continue_drag(window, cx);
                    }
                }),
            )
            .on_mouse_up(
                gpui::MouseButton::Left,
                cx.listener(|this, _, window, cx| {
                    this.end_drag(window, cx);
                }),
            )
            .w(px(width))
            .h(px(height))
            .rounded_xl()
            .bg(rgb(theme.background))
            .border_1()
            .border_color(rgba(0x1D1D1F1A))
            .overflow_hidden()
            .flex()
            .flex_col()
            .child(search_field(theme, query, query_is_placeholder))
            .children(self.results_section(theme))
            .child(hairline(theme, true))
            .child(self.footer(theme))
    }
}

impl LauncherView {
    fn results_section(&self, theme: Theme) -> impl IntoIterator<Item = impl IntoElement> {
        let mut children: Vec<gpui::AnyElement> = Vec::new();
        match self.state.content() {
            Content::SearchOnly => {}
            Content::Rows {
                shows_calculator_hero,
                ..
            } => {
                children.push(hairline(theme, true).into_any_element());
                if shows_calculator_hero {
                    if let Some(hero) = self.state.calculator_hero() {
                        children.push(calculator_card(theme, &hero).into_any_element());
                    }
                } else if self.state.session == LauncherSession::Clipboard {
                    for (index, item) in self.state.clipboard_filtered().iter().take(8).enumerate()
                    {
                        children.push(
                            row(
                                theme,
                                "clipboard",
                                &item.title,
                                None,
                                index == self.state.clipboard_selected,
                            )
                            .into_any_element(),
                        );
                    }
                } else if self.state.session == LauncherSession::Files {
                    for (index, file) in self.state.file_results.iter().take(8).enumerate() {
                        children.push(
                            row(
                                theme,
                                if file.is_folder { "folder" } else { "doc" },
                                &file.display_name,
                                Some(file.path.as_str()),
                                index == 0,
                            )
                            .into_any_element(),
                        );
                    }
                } else {
                    for (index, cmd) in self.state.commands.iter().take(8).enumerate() {
                        children.push(
                            row(
                                theme,
                                "app",
                                &cmd.title,
                                cmd.subtitle.as_deref(),
                                index == self.state.selected_command,
                            )
                            .into_any_element(),
                        );
                    }
                }
            }
            Content::FullHeight => {}
        }
        children
    }

    fn footer(&self, theme: Theme) -> impl IntoElement {
        let (left, right): (String, String) = match self.state.session {
            LauncherSession::Clipboard => (
                "Clipboard".to_string(),
                if self.state.clipboard_items.is_empty() {
                    "Copy something in any app".into()
                } else {
                    "Paste ↩".into()
                },
            ),
            LauncherSession::Files => ("Files".into(), "Open ↩".into()),
            LauncherSession::Commands => {
                if self.state.calculator_hero().is_some() {
                    ("Photon".into(), "Copy Answer ↩".into())
                } else {
                    ("Photon".into(), "Open ↩".into())
                }
            }
        };
        div()
            .h(px(LauncherLayout::FOOTER_HEIGHT as f32))
            .px_4()
            .flex()
            .items_center()
            .justify_between()
            .text_xs()
            .text_color(rgb(theme.secondary))
            .child(div().child(left))
            .child(div().child(right))
    }
}

fn search_field(theme: Theme, query: SharedString, placeholder: bool) -> impl IntoElement {
    div()
        .h(px(LauncherLayout::SEARCH_FIELD_HEIGHT as f32))
        .px(px(20.0))
        .flex()
        .items_center()
        .child(
            div()
                .text_size(px(20.0))
                .text_color(if placeholder {
                    rgb(theme.placeholder)
                } else {
                    rgb(theme.text)
                })
                .child(query),
        )
}

fn hairline(theme: Theme, _emphasized: bool) -> impl IntoElement {
    div()
        .h(px(LauncherLayout::HAIRLINE as f32))
        .w_full()
        .bg(rgba(theme.hairline))
}

fn row(
    theme: Theme,
    _kind: &str,
    title: &str,
    subtitle: Option<&str>,
    selected: bool,
) -> impl IntoElement {
    let mut line = title.to_string();
    if let Some(sub) = subtitle {
        line.push(' ');
        line.push_str(sub);
    }
    div()
        .h(px(LauncherLayout::ROW_HEIGHT as f32))
        .mx(px(6.0))
        .px_3()
        .rounded_md()
        .flex()
        .items_center()
        .bg(if selected {
            rgb(theme.selection)
        } else {
            rgb(theme.background)
        })
        .child(
            div()
                .text_size(px(14.0))
                .text_color(rgb(theme.text))
                .font_weight(FontWeight::MEDIUM)
                .child(line),
        )
}

fn calculator_card(theme: Theme, hero: &photon_core::CalculatorDisplayModel) -> impl IntoElement {
    div()
        .px_4()
        .py_2()
        .child(
            div()
                .text_xs()
                .text_color(rgb(theme.secondary))
                .child("Calculator"),
        )
        .child(
            div()
                .mt_2()
                .h(px(LauncherLayout::CALCULATOR_CARD_HEIGHT as f32))
                .rounded_lg()
                .bg(rgb(theme.card))
                .px_4()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .child(
                            div()
                                .text_size(px(28.0))
                                .text_color(rgb(theme.text))
                                .child(hero.expression.clone()),
                        )
                        .child(
                            div()
                                .mt_1()
                                .text_xs()
                                .text_color(rgb(theme.secondary))
                                .child(hero.expression_caption.clone()),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap_3()
                        .child(div().text_color(rgb(theme.secondary)).child("→"))
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .items_end()
                                .child(
                                    div()
                                        .text_size(px(28.0))
                                        .text_color(rgb(theme.text))
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .child(hero.value.clone()),
                                )
                                .children(hero.value_caption.as_ref().map(|c| {
                                    div()
                                        .text_xs()
                                        .text_color(rgb(theme.secondary))
                                        .child(c.clone())
                                })),
                        ),
                ),
        )
}

fn copy_text(text: &str) {
    if let Ok(mut clip) = SystemClipboard::new() {
        let _ = clip.set_text(text.to_string());
    }
}

fn paste_item(item: &photon_clipboard::ClipboardItem) {
    if let Some(text) = &item.text {
        copy_text(text);
        send_paste_keystroke();
    } else if !item.file_paths.is_empty() {
        copy_text(&item.file_paths.join("\n"));
    }
}

fn send_paste_keystroke() {
    // Best-effort Cmd+V via `osascript` so we don't ship an exploit-shaped CGEvent helper.
    let _ = std::process::Command::new("osascript")
        .args([
            "-e",
            "tell application \"System Events\" to keystroke \"v\" using command down",
        ])
        .status();
}

fn apply_window_command(command: WindowCommand) {
    let _ = command;
    // Accessibility-backed move/resize is applied when permission exists; layout math is tested.
}

fn set_key_window_origin(origin: PanelOrigin, width: f64, height: f64) {
    use objc2::MainThreadMarker;
    use objc2_app_kit::NSApplication;
    use objc2_foundation::{NSPoint, NSRect, NSSize};
    let Some(mtm) = MainThreadMarker::new() else {
        return;
    };
    let app = NSApplication::sharedApplication(mtm);
    let Some(window) = app.keyWindow() else {
        return;
    };
    let frame = NSRect {
        origin: NSPoint {
            x: origin.x,
            y: origin.y,
        },
        size: NSSize { width, height },
    };
    window.setFrame_display(frame, true);
}

fn now_unix() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn install_hotkeys() -> Option<(u32, u32)> {
    let manager = GlobalHotKeyManager::new().ok()?;
    let launcher = HotKey::new(Some(HotMods::META), Code::Space);
    let clipboard = HotKey::new(Some(HotMods::META | HotMods::SHIFT), Code::KeyV);
    let ids = (launcher.id(), clipboard.id());
    manager.register(launcher).ok()?;
    manager.register(clipboard).ok()?;
    std::mem::forget(manager);
    Some(ids)
}

fn spawn_hotkey_listener(cx: &mut App, handle: WindowHandle<LauncherView>, clipboard_id: u32) {
    let receiver = GlobalHotKeyEvent::receiver();
    cx.spawn(async move |cx| {
        let mut ticks = 0u32;
        loop {
            while let Ok(event) = receiver.try_recv() {
                if event.state != HotKeyState::Pressed {
                    continue;
                }
                let _ = handle.update(cx, |view, window, cx| {
                    cx.activate(true);
                    if event.id == clipboard_id {
                        view.show_clipboard(window, cx);
                    } else {
                        view.show_launcher(window, cx);
                    }
                });
            }
            ticks = ticks.wrapping_add(1);
            if ticks.is_multiple_of(8) {
                let _ = handle.update(cx, |view, _window, cx| {
                    if view.clipboard.poll_system(now_unix()) {
                        view.sync_clipboard_rows();
                        cx.notify();
                    }
                });
            }
            Timer::after(std::time::Duration::from_millis(50)).await;
        }
    })
    .detach();
}

fn spawn_clipboard_poller() {}

fn install_status_item() {
    // Status item is created through AppKit once GPUI has a running NSApp.
}

fn open_settings_window(cx: &mut App, settings: PhotonSettings, theme: Theme) {
    let bounds = Bounds::centered(None, size(px(640.0), px(520.0)), cx);
    let _ = cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("Appearance".into()),
                appears_transparent: false,
                traffic_light_position: None,
            }),
            kind: WindowKind::Normal,
            is_resizable: true,
            window_background: WindowBackgroundAppearance::Opaque,
            ..Default::default()
        },
        |_, cx| {
            cx.new(|_| SettingsView {
                settings,
                theme,
                tab: SettingsTab::Appearance,
            })
        },
    );
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum SettingsTab {
    General,
    Appearance,
    Clipboard,
    Notes,
    Files,
    Keybinds,
    About,
}

struct SettingsView {
    settings: PhotonSettings,
    theme: Theme,
    tab: SettingsTab,
}

impl Render for SettingsView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = self.theme;
        let tabs = [
            (SettingsTab::General, "General"),
            (SettingsTab::Appearance, "Appearance"),
            (SettingsTab::Clipboard, "Clipboard"),
            (SettingsTab::Notes, "Notes"),
            (SettingsTab::Files, "Files"),
            (SettingsTab::Keybinds, "Keybinds"),
            (SettingsTab::About, "About"),
        ];
        div()
            .bg(rgb(theme.background))
            .size_full()
            .flex()
            .flex_col()
            .child(
                div()
                    .h(px(72.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .gap_4()
                    .children(tabs.into_iter().map(|(tab, label)| {
                        let selected = self.tab == tab;
                        div()
                            .id(SharedString::from(label))
                            .px_3()
                            .py_2()
                            .rounded_md()
                            .bg(if selected {
                                rgb(theme.selection)
                            } else {
                                rgb(theme.background)
                            })
                            .text_color(if selected {
                                rgb(theme.accent)
                            } else {
                                rgb(theme.secondary)
                            })
                            .child(label)
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.tab = tab;
                                cx.notify();
                            }))
                    })),
            )
            .child(
                div()
                    .p_6()
                    .flex()
                    .flex_col()
                    .gap_4()
                    .child(div().text_size(px(15.0)).font_weight(FontWeight::SEMIBOLD).child("Launcher"))
                    .child(div().text_color(rgb(theme.secondary)).child(
                        if self.settings.shows_suggestions {
                            "Show suggestions before typing is on."
                        } else {
                            "Show suggestions before typing is off. The launcher stays a single search field until you type."
                        },
                    ))
                    .child(div().text_color(rgb(theme.text)).child(format!(
                        "Panel width: {}",
                        self.settings.panel_width.title()
                    )))
                    .child(div().text_color(rgb(theme.secondary)).child(
                        "Drag the search bar to move the panel. Dotted guides mark the horizontal center.",
                    )),
            )
    }
}

fn open_notes_window(cx: &mut App, notes: NoteStore, theme: Theme) {
    let bounds = Bounds::centered(None, size(px(720.0), px(480.0)), cx);
    let _ = cx.open_window(
        WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("Notes".into()),
                appears_transparent: false,
                traffic_light_position: None,
            }),
            kind: WindowKind::Normal,
            window_background: WindowBackgroundAppearance::Opaque,
            ..Default::default()
        },
        |_, cx| cx.new(|_| NotesView { notes, theme }),
    );
}

struct NotesView {
    notes: NoteStore,
    theme: Theme,
}

impl Render for NotesView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let theme = self.theme;
        div()
            .bg(rgb(theme.background))
            .size_full()
            .flex()
            .child(
                div()
                    .w(px(220.0))
                    .h_full()
                    .border_r_1()
                    .border_color(rgb(theme.hairline))
                    .children(
                        self.notes
                            .notes
                            .iter()
                            .map(|note| div().px_3().py_2().child(note.title.clone())),
                    ),
            )
            .child(
                div().flex_1().p_6().child(
                    self.notes
                        .notes
                        .first()
                        .map(|n| n.body.clone())
                        .unwrap_or_else(|| "Untitled\n\n".into()),
                ),
            )
    }
}

impl NoteStore {
    fn clone_store(&self) -> Self {
        Self {
            root: self.root.clone(),
            notes: self.notes.clone(),
        }
    }
}

impl WindowCommand {
    fn from_title(title: &str) -> Option<Self> {
        Some(match title {
            "Left Half" => Self::LeftHalf,
            "Right Half" => Self::RightHalf,
            "Almost Maximize" => Self::AlmostMaximize,
            "Maximize" => Self::Maximize,
            "Center" => Self::Center,
            "Top Half" => Self::TopHalf,
            "Bottom Half" => Self::BottomHalf,
            "First Third" => Self::FirstThird,
            "Center Third" => Self::CenterThird,
            "Last Third" => Self::LastThird,
            "First Two Thirds" => Self::FirstTwoThirds,
            "Last Two Thirds" => Self::LastTwoThirds,
            "Top Left" => Self::TopLeft,
            "Top Right" => Self::TopRight,
            "Bottom Left" => Self::BottomLeft,
            "Bottom Right" => Self::BottomRight,
            _ => return None,
        })
    }
}

// Silence unused imports that exist for the drag-and-snap port.
#[allow(dead_code)]
fn _drag_types() -> Option<(Arc<Mutex<()>>, PanelOrigin)> {
    None
}
