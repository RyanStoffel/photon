//! Clipboard history: persist text/links/images/files, pin, paste/copy, excluded apps.

mod history;
mod item;
mod search;
mod store;

pub use history::{ClipboardHistory, InsertOutcome};
pub use item::{
    ClipboardContent, ClipboardItem, ClipboardItemKind, ClipboardPasteBehavior, ClipboardRetention,
    ClipboardSettings,
};
pub use search::ClipboardSearch;
pub use store::ClipboardStore;
