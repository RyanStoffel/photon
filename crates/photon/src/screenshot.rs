use photon_core::screenshot::ScreenshotScenario;

pub fn current_scenario() -> Option<ScreenshotScenario> {
    if let Ok(raw) = std::env::var("PHOTON_UI_SCENARIO") {
        if !raw.is_empty() {
            return ScreenshotScenario::parse(&raw);
        }
    }
    let args: Vec<String> = std::env::args().collect();
    if let Some(index) = args.iter().position(|a| a == "--ui-scenario") {
        if let Some(value) = args.get(index + 1) {
            return ScreenshotScenario::parse(value);
        }
    }
    None
}

pub fn mark_ready() {
    if let Ok(path) = std::env::var("PHOTON_UI_SCENARIO_READY_PATH") {
        if !path.is_empty() {
            std::fs::write(path, "ready").ok();
        }
    }
}
