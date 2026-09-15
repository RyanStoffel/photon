use photon_core::fuzzy::FuzzyMatcher;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppEntry {
    pub id: String,
    pub name: String,
    pub path: String,
    pub bundle_id: Option<String>,
    pub subtitle: Option<String>,
    pub keywords: Vec<String>,
}

pub fn scan_applications(extra_roots: &[String]) -> Vec<AppEntry> {
    let mut roots = vec![
        "/Applications".into(),
        "/System/Applications".into(),
        "/System/Applications/Utilities".into(),
    ];
    if let Some(home) = dirs::home_dir() {
        roots.push(home.join("Applications").to_string_lossy().into_owned());
    }
    roots.extend(extra_roots.iter().cloned());
    let mut apps = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for root in roots {
        let path = std::path::Path::new(&root);
        if !path.is_dir() {
            continue;
        }
        let Ok(entries) = std::fs::read_dir(path) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("app") {
                continue;
            }
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("App")
                .to_string();
            let id = path.to_string_lossy().into_owned();
            if !seen.insert(id.clone()) {
                continue;
            }
            apps.push(AppEntry {
                id: format!("app:{id}"),
                name,
                path: id,
                bundle_id: None,
                subtitle: None,
                keywords: Vec::new(),
            });
        }
    }
    apps.extend(system_settings_panes());
    apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    apps
}

pub fn search_apps<'a>(apps: &'a [AppEntry], query: &str) -> Vec<&'a AppEntry> {
    if query.is_empty() {
        return apps.iter().take(8).collect();
    }
    let mut scored: Vec<(f64, &AppEntry)> = apps
        .iter()
        .filter_map(|app| {
            let mut best = FuzzyMatcher::score(query, &app.name)?;
            for keyword in &app.keywords {
                if let Some(score) = FuzzyMatcher::score(query, keyword) {
                    best = best.max(score);
                }
            }
            Some((best, app))
        })
        .collect();
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
    scored.into_iter().map(|(_, app)| app).take(30).collect()
}

fn system_settings_panes() -> Vec<AppEntry> {
    const PANES: &[(&str, &str, &[&str])] = &[
        (
            "Accessibility",
            "x-apple.systempreferences:com.apple.preference.universalaccess",
            &["a11y"],
        ),
        (
            "Appearance",
            "x-apple.systempreferences:com.apple.Appearance-Settings.extension",
            &[],
        ),
        (
            "Apple ID",
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
            &[],
        ),
        (
            "Battery",
            "x-apple.systempreferences:com.apple.preference.battery",
            &["energy"],
        ),
        (
            "Bluetooth",
            "x-apple.systempreferences:com.apple.BluetoothSettings",
            &[],
        ),
        (
            "Date & Time",
            "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
            &[],
        ),
        (
            "Desktop & Dock",
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            &["dock"],
        ),
        (
            "Displays",
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            &[],
        ),
        (
            "Family Sharing Pref Pane",
            "x-apple.systempreferences:com.apple.preferences.FamilySharingPrefPane",
            &["family"],
        ),
        (
            "Keyboard",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            &[],
        ),
        (
            "Network",
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            &["wifi"],
        ),
        (
            "Notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            &[],
        ),
        (
            "Passwords",
            "x-apple.systempreferences:com.apple.Passwords-Settings.extension",
            &[],
        ),
        (
            "Privacy & Security",
            "x-apple.systempreferences:com.apple.preference.security",
            &["privacy"],
        ),
        (
            "Sound",
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            &[],
        ),
        (
            "Wallpaper",
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            &["desktop"],
        ),
        (
            "Wi-Fi",
            "x-apple.systempreferences:com.apple.wifi-settings-extension",
            &["wifi", "network"],
        ),
    ];
    PANES
        .iter()
        .map(|(name, url, aliases)| AppEntry {
            id: format!("pane:{url}"),
            name: (*name).to_string(),
            path: (*url).to_string(),
            bundle_id: None,
            subtitle: Some("System Settings".into()),
            keywords: aliases.iter().map(|s| (*s).to_string()).collect(),
        })
        .collect()
}

pub fn open_entry(entry: &AppEntry) -> std::io::Result<()> {
    std::process::Command::new("open")
        .arg(&entry.path)
        .status()
        .map(|_| ())
}
