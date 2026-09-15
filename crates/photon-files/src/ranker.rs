use crate::fuzzy::FileFuzzyMatcher;
use crate::mdfind::SpotlightQueryBuilder;
use crate::path::PathFormatter;
use crate::result::FileResult;
use crate::scope::FilePathScope;
use crate::settings::FileSearchScope;

#[derive(Debug, Clone, PartialEq)]
pub struct RankedFile {
    pub file: FileResult,
    pub relevance: f64,
}

pub struct FileRanker;

impl FileRanker {
    pub const STRONG_MATCH_THRESHOLD: f64 = 0.7;

    #[allow(clippy::too_many_arguments)]
    pub fn rank(
        files: &[FileResult],
        query: &str,
        excluded_folders: &[String],
        include_applications: bool,
        limit: usize,
        home: &str,
        scope: FileSearchScope,
        extra_folders: &[String],
    ) -> Vec<RankedFile> {
        if limit == 0 {
            return Vec::new();
        }
        let terms: Vec<String> = SpotlightQueryBuilder::terms(query)
            .into_iter()
            .map(|t| fold(&t))
            .collect();
        let whole_query = terms.join(" ");
        let exclusions = normalized_folders(excluded_folders, home);
        let mut seen = std::collections::HashSet::new();
        let mut ranked: Vec<RankedFile> = files
            .iter()
            .filter_map(|file| {
                if !seen.insert(file.path.clone()) {
                    return None;
                }
                if !include_applications && file.is_application {
                    return None;
                }
                if is_excluded(&file.path, &exclusions) {
                    return None;
                }
                if scope == FileSearchScope::Home {
                    if FilePathScope::is_blocked_system_path(&file.path, home) {
                        return None;
                    }
                    if !FilePathScope::is_allowed(&file.path, scope, home, extra_folders) {
                        return None;
                    }
                }
                let score = relevance_of(file, &terms, &whole_query, home);
                if score <= 0.0 {
                    return None;
                }
                Some(RankedFile {
                    file: file.clone(),
                    relevance: score,
                })
            })
            .collect();
        ranked.sort_by(precedes);
        ranked.truncate(limit);
        ranked
    }

    pub fn relevance(file: &FileResult, query: &str, home: &str) -> f64 {
        let terms: Vec<String> = SpotlightQueryBuilder::terms(query)
            .into_iter()
            .map(|t| fold(&t))
            .collect();
        let whole = terms.join(" ");
        relevance_of(file, &terms, &whole, home)
    }

    pub fn is_excluded(path: &str, folders: &[String], home: &str) -> bool {
        is_excluded(path, &normalized_folders(folders, home))
    }
}

fn relevance_of(file: &FileResult, terms: &[String], whole_query: &str, home: &str) -> f64 {
    if terms.is_empty() {
        return 0.0;
    }
    let relative = PathFormatter::relative_to_home(&file.path, home).unwrap_or(file.path.clone());
    let whole = score(whole_query, file.stem(), &file.file_name, &relative);
    let bonus = if terms.len() == 1 {
        first_token_bonus(file, &terms[0])
    } else {
        0.0
    };
    if terms.len() == 1 {
        return whole.max(bonus).min(1.0);
    }
    let per_term: Vec<f64> = terms
        .iter()
        .map(|term| score(term, file.stem(), &file.file_name, &relative))
        .collect();
    if per_term.contains(&0.0) {
        return 0.0;
    }
    let averaged = per_term.iter().sum::<f64>() / per_term.len() as f64;
    whole.max(averaged).max(bonus).min(1.0)
}

fn score(query: &str, stem: &str, file_name: &str, relative_path: &str) -> f64 {
    let folded = fold(query);
    if folded.is_empty() {
        return 0.0;
    }
    if fold(stem) == folded {
        return 1.0;
    }
    let mut weighted: f64 = 0.0;
    if let Some(stem_score) = FileFuzzyMatcher::score(query, stem) {
        weighted = weighted.max(stem_score);
    }
    if let Some(name_score) = FileFuzzyMatcher::score(query, file_name) {
        weighted = weighted.max(name_score * 0.92);
    }
    if let Some(path_score) = FileFuzzyMatcher::score(query, relative_path) {
        weighted = weighted.max(path_score * 0.78);
    }
    if weighted <= 0.0 {
        return 0.0;
    }
    if fold(stem).starts_with(&folded) {
        weighted = weighted.max(0.85);
    }
    if word_start_indices(stem).into_iter().any(|index| {
        fold(stem)
            .chars()
            .skip(index)
            .collect::<String>()
            .starts_with(&folded)
    }) {
        weighted = weighted.max(0.7);
    }
    weighted.min(1.0)
}

/// Documents whose first filename token equals the query (Ember_Individual_Pitch
/// for `ember`) outrank a screenful of similarly prefixed folders.
fn first_token_bonus(file: &FileResult, folded_query: &str) -> f64 {
    if file.is_folder || folded_query.is_empty() {
        return 0.0;
    }
    let Some(token) = SpotlightQueryBuilder::terms(file.stem())
        .first()
        .map(|t| fold(t))
    else {
        return 0.0;
    };
    if token == folded_query {
        0.93
    } else {
        0.0
    }
}

fn word_start_indices(text: &str) -> Vec<usize> {
    let chars: Vec<char> = text.chars().collect();
    let mut starts = Vec::new();
    for index in 0..chars.len() {
        if index == 0 {
            starts.push(0);
            continue;
        }
        let previous = chars[index - 1];
        let current = chars[index];
        if !previous.is_alphanumeric() {
            if current.is_alphanumeric() {
                starts.push(index);
            }
        } else if previous.is_lowercase() && current.is_uppercase() {
            starts.push(index);
        } else if previous.is_alphabetic() && current.is_ascii_digit() {
            starts.push(index);
        }
    }
    starts
}

fn fold(text: &str) -> String {
    text.chars().flat_map(|c| c.to_lowercase()).collect()
}

fn precedes(lhs: &RankedFile, rhs: &RankedFile) -> std::cmp::Ordering {
    rhs.relevance
        .partial_cmp(&lhs.relevance)
        .unwrap_or(std::cmp::Ordering::Equal)
        .then_with(|| compare_dates(lhs.file.last_used, rhs.file.last_used))
        .then_with(|| compare_dates(lhs.file.modified, rhs.file.modified))
        .then_with(|| {
            lhs.file
                .display_name
                .to_lowercase()
                .cmp(&rhs.file.display_name.to_lowercase())
        })
        .then_with(|| lhs.file.path.len().cmp(&rhs.file.path.len()))
}

fn compare_dates(lhs: Option<f64>, rhs: Option<f64>) -> std::cmp::Ordering {
    match (lhs, rhs) {
        (Some(a), Some(b)) if (a - b).abs() < f64::EPSILON => std::cmp::Ordering::Equal,
        (Some(a), Some(b)) => b.partial_cmp(&a).unwrap_or(std::cmp::Ordering::Equal),
        (Some(_), None) => std::cmp::Ordering::Less,
        (None, Some(_)) => std::cmp::Ordering::Greater,
        (None, None) => std::cmp::Ordering::Equal,
    }
}

pub fn normalized_folders(folders: &[String], home: &str) -> Vec<String> {
    folders
        .iter()
        .filter_map(|folder| {
            let mut path = folder.trim().to_string();
            if path == "~" {
                path = home.to_string();
            } else if let Some(rest) = path.strip_prefix("~/") {
                path = format!("{home}/{rest}");
            }
            while path.len() > 1 && path.ends_with('/') {
                path.pop();
            }
            if path.is_empty() {
                None
            } else {
                Some(path)
            }
        })
        .collect()
}

fn is_excluded(path: &str, folders: &[String]) -> bool {
    folders
        .iter()
        .any(|folder| folder == "/" || path == folder || path.starts_with(&format!("{folder}/")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(path: &str, is_folder: bool) -> FileResult {
        let name = std::path::Path::new(path)
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        FileResult {
            path: path.into(),
            display_name: name.clone(),
            file_name: name,
            kind: if is_folder { "Folder" } else { "Document" }.into(),
            content_type: None,
            is_folder,
            is_application: false,
            size: None,
            created: None,
            modified: None,
            last_used: None,
        }
    }

    #[test]
    fn ember_surfaces_pitch_pdf_above_prefixed_folders() {
        let home = "/Users/ryan";
        let exact_folder = file("/Users/ryan/Developer/school/capstone/ember", true);
        let poc = file("/Users/ryan/Developer/school/capstone/ember_poc", true);
        let pdf = file(
            "/Users/ryan/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf",
            false,
        );
        let ranked = FileRanker::rank(
            &[poc.clone(), pdf.clone(), exact_folder.clone()],
            "ember",
            &[],
            true,
            10,
            home,
            FileSearchScope::Home,
            &[],
        );
        assert_eq!(
            ranked
                .iter()
                .map(|r| r.file.path.as_str())
                .collect::<Vec<_>>(),
            vec![
                exact_folder.path.as_str(),
                pdf.path.as_str(),
                poc.path.as_str()
            ]
        );
        assert!(ranked[1].relevance >= 0.93);
    }
}
