use crate::ranker::normalized_folders;
use crate::settings::FileSearchScope;

pub struct FilePathScope;

impl FilePathScope {
    pub fn is_allowed(
        path: &str,
        scope: FileSearchScope,
        home: &str,
        extra_folders: &[String],
    ) -> bool {
        match scope {
            FileSearchScope::Computer => true,
            FileSearchScope::Home => {
                let resolved = crate::path::PathFormatter::resolving_firmlink(path);
                let home = normalize_directory(home);
                if resolved == home || resolved.starts_with(&format!("{home}/")) {
                    return true;
                }
                let extras = normalized_folders(extra_folders, &home);
                extras.iter().any(|folder| {
                    resolved == *folder || resolved.starts_with(&format!("{folder}/"))
                })
            }
        }
    }

    pub fn is_blocked_system_path(path: &str, home: &str) -> bool {
        let resolved = crate::path::PathFormatter::resolving_firmlink(path);
        let home = normalize_directory(home);
        if Self::is_allowed(&resolved, FileSearchScope::Home, &home, &[]) {
            return false;
        }
        resolved.starts_with("/System")
            || resolved == "/Library"
            || resolved.starts_with("/Library/")
            || resolved.starts_with("/private")
            || resolved == "/usr"
            || resolved.starts_with("/usr")
            || resolved == "/bin"
            || resolved.starts_with("/bin")
    }
}

fn normalize_directory(path: &str) -> String {
    let mut trimmed = path.to_string();
    while trimmed.len() > 1 && trimmed.ends_with('/') {
        trimmed.pop();
    }
    trimmed
}
