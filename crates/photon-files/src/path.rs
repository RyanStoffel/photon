pub struct PathFormatter;

impl PathFormatter {
    pub const ELLIPSIS: &'static str = "\u{2026}";

    pub fn resolving_firmlink(path: &str) -> String {
        const PREFIX: &str = "/System/Volumes/Data";
        if path == PREFIX {
            return "/".into();
        }
        if let Some(rest) = path.strip_prefix(&format!("{PREFIX}/")) {
            format!("/{rest}")
        } else {
            path.to_string()
        }
    }

    pub fn abbreviating_home(path: &str, home: &str) -> String {
        let resolved = Self::resolving_firmlink(path);
        let root = home.trim_end_matches('/');
        if resolved == root {
            return "~".into();
        }
        if let Some(rest) = resolved.strip_prefix(&format!("{root}/")) {
            format!("~/{rest}")
        } else {
            resolved
        }
    }

    pub fn relative_to_home(path: &str, home: &str) -> Option<String> {
        let resolved = Self::resolving_firmlink(path);
        let root = home.trim_end_matches('/');
        if resolved == root {
            return Some(String::new());
        }
        resolved
            .strip_prefix(&format!("{root}/"))
            .map(str::to_string)
    }

    pub fn parent_display(path: &str, max_length: usize, home: &str) -> String {
        let parent = std::path::Path::new(path)
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .filter(|p| !p.is_empty())
            .unwrap_or_else(|| "/".into());
        let abbreviated = Self::abbreviating_home(&parent, home);
        Self::middle_truncated(&abbreviated, max_length)
    }

    pub fn middle_truncated(path: &str, max_length: usize) -> String {
        if max_length == 0 || path.chars().count() <= max_length {
            return path.to_string();
        }
        if max_length <= 2 {
            return path.chars().take(max_length).collect();
        }
        let keep = max_length - 1;
        let head = keep / 2;
        let tail = keep - head;
        let chars: Vec<char> = path.chars().collect();
        let mut out: String = chars.iter().take(head).collect();
        out.push('…');
        out.extend(
            chars
                .iter()
                .rev()
                .take(tail)
                .collect::<Vec<_>>()
                .into_iter()
                .rev(),
        );
        out
    }
}
