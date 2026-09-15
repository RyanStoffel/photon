use std::fs;
use std::path::{Path, PathBuf};

use photon_core::fuzzy::FuzzyMatcher;

#[derive(Debug, Clone)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub body: String,
    pub path: PathBuf,
}

pub struct NoteStore {
    pub root: PathBuf,
    pub notes: Vec<Note>,
}

impl NoteStore {
    pub fn load(root: impl AsRef<Path>) -> Self {
        let root = root.as_ref().join("Notes");
        fs::create_dir_all(&root).ok();
        let mut notes = Vec::new();
        if let Ok(entries) = fs::read_dir(&root) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) != Some("md") {
                    continue;
                }
                let body = fs::read_to_string(&path).unwrap_or_default();
                let title = title_of(&body, &path);
                notes.push(Note {
                    id: path.to_string_lossy().into_owned(),
                    title,
                    body,
                    path,
                });
            }
        }
        notes.sort_by(|a, b| b.path.cmp(&a.path));
        Self { root, notes }
    }

    pub fn create(&mut self, title: &str) -> Note {
        let slug = if title.is_empty() { "Untitled" } else { title };
        let path = unique_path(&self.root, slug);
        let body = format!("{slug}\n\n");
        fs::write(&path, &body).ok();
        let note = Note {
            id: path.to_string_lossy().into_owned(),
            title: slug.into(),
            body,
            path,
        };
        self.notes.insert(0, note.clone());
        note
    }

    pub fn save(&mut self, id: &str, body: String) {
        if let Some(note) = self.notes.iter_mut().find(|n| n.id == id) {
            note.body = body.clone();
            note.title = title_of(&body, &note.path);
            fs::write(&note.path, body).ok();
        }
    }

    pub fn search<'a>(&'a self, query: &str) -> Vec<&'a Note> {
        if query.is_empty() {
            return self.notes.iter().collect();
        }
        self.notes
            .iter()
            .filter(|note| {
                FuzzyMatcher::matches(query, &note.title)
                    || note.body.to_lowercase().contains(&query.to_lowercase())
            })
            .collect()
    }
}

fn title_of(body: &str, path: &Path) -> String {
    body.lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(|l| l.trim_start_matches('#').trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Untitled")
                .to_string()
        })
}

fn unique_path(root: &Path, title: &str) -> PathBuf {
    let slug: String = title
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect();
    let mut path = root.join(format!("{slug}.md"));
    let mut i = 2;
    while path.exists() {
        path = root.join(format!("{slug}-{i}.md"));
        i += 1;
    }
    path
}
