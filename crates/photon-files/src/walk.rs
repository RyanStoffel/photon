use std::path::Path;

use walkdir::WalkDir;

use crate::mdfind::SpotlightQueryBuilder;
use crate::result::FileResult;

const SKIP_DIR_NAMES: &[&str] = &[
    ".git",
    "node_modules",
    "target",
    "Library",
    ".build",
    "DerivedData",
    "__pycache__",
    ".Trash",
];

/// Walk `root` and collect files/folders whose basename matches query tokens.
/// This is the CI-proof path: GitHub-hosted Macs often have an empty Spotlight
/// index, so `mdfind -onlyin` returns nothing. A fixture home is small and still
/// finds `Ember_Individual_Pitch.pdf`.
pub fn walk_basename_matches(root: &Path, query: &str, limit: usize) -> Vec<FileResult> {
    let terms: Vec<String> = SpotlightQueryBuilder::terms(query)
        .into_iter()
        .map(|t| t.to_lowercase())
        .collect();
    if terms.is_empty() || limit == 0 {
        return Vec::new();
    }
    let mut out = Vec::new();
    for entry in WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            if e.file_type().is_dir() {
                let name = e.file_name().to_string_lossy();
                !SKIP_DIR_NAMES
                    .iter()
                    .any(|skip| name.eq_ignore_ascii_case(skip))
            } else {
                true
            }
        })
        .flatten()
    {
        if out.len() >= limit {
            break;
        }
        let path = entry.path();
        if path == root {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_lowercase();
        let alnum: String = name.chars().filter(|c| c.is_alphanumeric()).collect();
        let matches = terms
            .iter()
            .all(|term| name.contains(term) || alnum.contains(term));
        if !matches {
            continue;
        }
        if let Some(file) = FileResult::from_path(path) {
            out.push(file);
        }
    }
    out
}
