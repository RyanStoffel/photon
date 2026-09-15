#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileSearchScope {
    Home,
    Computer,
}

impl FileSearchScope {
    pub fn parse(raw: &str) -> Self {
        if raw == "this-mac" || raw == "computer" {
            Self::Computer
        } else {
            Self::Home
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileDefaultAction {
    Open,
    Reveal,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FileSearchSettings {
    pub scope: FileSearchScope,
    pub extra_folders: Vec<String>,
    pub excluded_folders: Vec<String>,
    pub search_contents: bool,
    pub max_results: usize,
    pub default_action: FileDefaultAction,
    pub inline_results: bool,
}

impl Default for FileSearchSettings {
    fn default() -> Self {
        Self {
            scope: FileSearchScope::Home,
            extra_folders: Vec::new(),
            excluded_folders: Vec::new(),
            search_contents: false,
            max_results: 50,
            default_action: FileDefaultAction::Open,
            inline_results: true,
        }
    }
}

impl FileSearchSettings {
    pub fn clamped_max_results(&self) -> usize {
        self.max_results.clamp(10, 200)
    }
}
