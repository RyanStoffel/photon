//! Clipboard capture helpers. On macOS this talks to NSPasteboard; elsewhere it is a stub.

use photon_clipboard::{ClipboardHistory, ClipboardItem, ClipboardSettings, ClipboardStore};
use uuid::Uuid;

pub struct ClipboardRuntime {
    pub store: ClipboardStore,
    pub history: ClipboardHistory,
    pub settings: ClipboardSettings,
    last_hash: Option<String>,
}

impl ClipboardRuntime {
    pub fn load(root: impl AsRef<std::path::Path>, settings: ClipboardSettings) -> Self {
        let store = ClipboardStore::new(root.as_ref().join("Clipboard"));
        let history = store.load();
        Self {
            store,
            history,
            settings,
            last_hash: None,
        }
    }

    pub fn persist(&self) {
        self.store.save(&self.history).ok();
    }

    pub fn ingest_text(&mut self, text: &str, bundle_id: Option<&str>, now: f64) {
        if !self.settings.is_enabled {
            return;
        }
        if self.settings.is_excluded(bundle_id) {
            return;
        }
        if text.is_empty() {
            return;
        }
        let mut item = ClipboardItem::text(text, now, false);
        item.source_bundle_id = bundle_id.map(str::to_string);
        self.insert(item);
    }

    pub fn ingest_image(&mut self, png: Vec<u8>, width: u32, height: u32, now: f64) {
        if !self.settings.is_enabled || png.is_empty() {
            return;
        }
        self.insert(ClipboardItem::image(png, width, height, now));
    }

    pub fn ingest_files(&mut self, paths: Vec<String>, now: f64) {
        if !self.settings.is_enabled || paths.is_empty() {
            return;
        }
        self.insert(ClipboardItem::files(paths, now));
    }

    pub fn toggle_pin(&mut self, id: Uuid) {
        self.history.toggle_pin(id);
        self.persist();
    }

    fn insert(&mut self, item: photon_clipboard::ClipboardItem) {
        if self.last_hash.as_deref() == Some(&item.content_hash) {
            return;
        }
        self.last_hash = Some(item.content_hash.clone());
        self.history.insert(item);
        let now = self
            .history
            .items
            .first()
            .map(|item| item.copied_at)
            .unwrap_or(0.0);
        self.history
            .prune(self.settings.retention, self.settings.max_items, now);
        self.persist();
    }

    /// Best-effort poll of the system pasteboard. Returns true when history changed.
    pub fn poll_system(&mut self, now: f64) -> bool {
        if !self.settings.is_enabled {
            return false;
        }
        let before = self.last_hash.clone();
        let bundle = frontmost_bundle_id();
        if self.settings.is_excluded(bundle.as_deref()) {
            return false;
        }
        #[cfg(target_os = "macos")]
        if let Some(paths) = macos_file_urls() {
            self.ingest_files(paths, now);
            return self.last_hash != before;
        }
        if let Ok(mut clip) = arboard::Clipboard::new() {
            if let Ok(image) = clip.get_image() {
                let width = image.width as u32;
                let height = image.height as u32;
                if let Some(png) = encode_png(width, height, &image.bytes) {
                    self.ingest_image(png, width, height, now);
                    return self.last_hash != before;
                }
            }
            if let Ok(text) = clip.get_text() {
                self.ingest_text(&text, bundle.as_deref(), now);
            }
        }
        self.last_hash != before
    }
}

fn encode_png(width: u32, height: u32, rgba: &[u8]) -> Option<Vec<u8>> {
    if width == 0 || height == 0 {
        return None;
    }
    let mut buf = Vec::new();
    let mut encoder = png::Encoder::new(&mut buf, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().ok()?;
    writer.write_image_data(rgba).ok()?;
    drop(writer);
    Some(buf)
}

#[cfg(target_os = "macos")]
fn frontmost_bundle_id() -> Option<String> {
    use objc2_app_kit::NSWorkspace;
    let workspace = NSWorkspace::sharedWorkspace();
    let app = workspace.frontmostApplication()?;
    app.bundleIdentifier().map(|s| s.to_string())
}

#[cfg(not(target_os = "macos"))]
fn frontmost_bundle_id() -> Option<String> {
    None
}

#[cfg(target_os = "macos")]
fn macos_file_urls() -> Option<Vec<String>> {
    use objc2::rc::Retained;
    use objc2_app_kit::{NSPasteboard, NSPasteboardTypeFileURL};
    use objc2_foundation::{NSString, NSURL};
    let pasteboard = NSPasteboard::generalPasteboard();
    let items = pasteboard.pasteboardItems()?;
    if items.count() == 0 {
        return None;
    }
    let mut paths = Vec::new();
    for item in items.iter() {
        let Some(value) = item.stringForType(unsafe { NSPasteboardTypeFileURL }) else {
            continue;
        };
        let url_string: Retained<NSString> = value;
        let Some(url) = NSURL::URLWithString(&url_string) else {
            continue;
        };
        if let Some(path) = url.path() {
            let owned = path.to_string();
            if !owned.is_empty() {
                paths.push(owned);
            }
        }
    }
    if paths.is_empty() {
        None
    } else {
        Some(paths)
    }
}
