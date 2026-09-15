use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::mdfind::{MdfindInvocation, SpotlightQueryBuilder};
use crate::ranker::FileRanker;
use crate::result::FileResult;
use crate::settings::{FileSearchScope, FileSearchSettings};
use crate::walk::walk_basename_matches;
use crate::RankedFile;

#[derive(Debug, Clone)]
pub struct FileSearchRequest {
    pub query: String,
    pub settings: FileSearchSettings,
    pub limit: usize,
    pub include_applications: bool,
    pub home: PathBuf,
}

#[derive(Debug, Clone)]
pub struct FileSearchResponse {
    pub query: String,
    pub files: Vec<RankedFile>,
    pub spotlight_available: bool,
}

pub struct FileSearchEngine {
    pub mdfind_timeout: Duration,
}

impl Default for FileSearchEngine {
    fn default() -> Self {
        Self {
            mdfind_timeout: Duration::from_millis(1800),
        }
    }
}

impl FileSearchEngine {
    pub fn only_in_folders(settings: &FileSearchSettings, home: &Path) -> Vec<String> {
        let mut folders = Vec::new();
        if settings.scope == FileSearchScope::Home {
            folders.push(home.to_string_lossy().into_owned());
        }
        for extra in &settings.extra_folders {
            if extra.starts_with('/') && !folders.contains(extra) {
                folders.push(extra.clone());
            }
        }
        folders
    }

    /// Search using `mdfind` (metadata + `-name`) and a basename walk of `home`.
    /// The walk guarantees the fixture/`mdfind -onlyin` test dir still passes when
    /// Spotlight's index is empty.
    pub fn search(&self, request: &FileSearchRequest) -> FileSearchResponse {
        let trimmed = request.query.trim();
        let Some(query_string) =
            SpotlightQueryBuilder::query_string(trimmed, request.settings.search_contents)
        else {
            return FileSearchResponse {
                query: trimmed.into(),
                files: Vec::new(),
                spotlight_available: true,
            };
        };

        let folders = Self::only_in_folders(&request.settings, &request.home);
        let scan_limit = 500.max(request.limit * 20);
        let terms = SpotlightQueryBuilder::terms(trimmed);
        let mut paths = Vec::new();
        let mut spotlight_available = true;

        let metadata = self.run_mdfind(Some(&query_string), None, &folders, scan_limit);
        spotlight_available &= metadata.available;
        paths.extend(metadata.paths);

        for term in &terms {
            let named = self.run_mdfind(None, Some(term), &folders, scan_limit);
            spotlight_available &= named.available;
            paths.extend(named.paths);
        }

        let walk_root = if folders.is_empty() {
            request.home.clone()
        } else {
            PathBuf::from(&folders[0])
        };
        for file in walk_basename_matches(&walk_root, trimmed, scan_limit) {
            paths.push(file.path);
        }

        let mut seen = std::collections::HashSet::new();
        let files: Vec<FileResult> = paths
            .into_iter()
            .filter(|p| seen.insert(p.clone()))
            .filter_map(FileResult::from_path)
            .collect();

        let ranked = FileRanker::rank(
            &files,
            trimmed,
            &request.settings.excluded_folders,
            request.include_applications,
            request.limit,
            &request.home.to_string_lossy(),
            request.settings.scope,
            &request.settings.extra_folders,
        );
        FileSearchResponse {
            query: trimmed.into(),
            files: ranked,
            spotlight_available,
        }
    }

    fn run_mdfind(
        &self,
        query_string: Option<&str>,
        file_name: Option<&str>,
        only_in: &[String],
        scan_limit: usize,
    ) -> MdfindOutcome {
        if !Path::new(MdfindInvocation::EXECUTABLE).is_file() {
            return MdfindOutcome {
                paths: Vec::new(),
                available: false,
            };
        }
        let args = MdfindInvocation::arguments(query_string, file_name, only_in);
        let started = Instant::now();
        let output = Command::new(MdfindInvocation::EXECUTABLE)
            .args(&args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        if started.elapsed() > self.mdfind_timeout {
            return MdfindOutcome {
                paths: Vec::new(),
                available: true,
            };
        }
        match output {
            Ok(out) => MdfindOutcome {
                paths: MdfindInvocation::paths_from_null_terminated(&out.stdout, scan_limit),
                available: out.status.success(),
            },
            Err(_) => MdfindOutcome {
                paths: Vec::new(),
                available: false,
            },
        }
    }
}

struct MdfindOutcome {
    paths: Vec<String>,
    available: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn fixture_home() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "photon-home-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let docs = dir.join("Documents/School/Capstone/Individual Pitch");
        let dev = dir.join("Developer/school/capstone/ember");
        fs::create_dir_all(&docs).unwrap();
        fs::create_dir_all(&dev).unwrap();
        fs::create_dir_all(dir.join("Developer/school/capstone/ember_poc")).unwrap();
        fs::write(docs.join("Ember_Individual_Pitch.pdf"), b"%PDF-1.4 ember").unwrap();
        fs::write(dir.join("Documents/notes.txt"), b"hello").unwrap();
        dir
    }

    #[test]
    fn ember_ranks_pitch_pdf_from_fixture_without_spotlight_index() {
        let home = fixture_home();
        let engine = FileSearchEngine::default();
        let response = engine.search(&FileSearchRequest {
            query: "ember".into(),
            settings: FileSearchSettings::default(),
            limit: 20,
            include_applications: false,
            home: home.clone(),
        });
        let pdf = response
            .files
            .iter()
            .find(|f| f.file.file_name == "Ember_Individual_Pitch.pdf")
            .unwrap_or_else(|| panic!("ember missed the Documents PDF: {:?}", response.files));
        assert!(pdf.relevance >= 0.93, "PDF relevance was {}", pdf.relevance);
        assert!(response
            .files
            .iter()
            .any(|f| f.file.file_name == "Ember_Individual_Pitch.pdf"));
        fs::remove_dir_all(&home).ok();
    }

    #[test]
    fn empty_query_does_not_search() {
        let engine = FileSearchEngine::default();
        let response = engine.search(&FileSearchRequest {
            query: "   ".into(),
            settings: FileSearchSettings::default(),
            limit: 10,
            include_applications: true,
            home: PathBuf::from("/tmp"),
        });
        assert!(response.files.is_empty());
    }
}
