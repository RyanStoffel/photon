//! Home-only Spotlight/`mdfind` plus filename/basename matching.

mod engine;
mod fuzzy;
mod mdfind;
mod path;
mod ranker;
mod result;
mod scope;
mod settings;
mod walk;

pub use engine::{FileSearchEngine, FileSearchRequest, FileSearchResponse};
pub use mdfind::MdfindInvocation;
pub use path::PathFormatter;
pub use ranker::{FileRanker, RankedFile};
pub use result::FileResult;
pub use scope::FilePathScope;
pub use settings::{FileDefaultAction, FileSearchScope, FileSearchSettings};
pub use walk::walk_basename_matches;
