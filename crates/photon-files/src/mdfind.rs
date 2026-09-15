//! Builds raw Spotlight query strings and splits alphanumeric tokens.

pub struct SpotlightQueryBuilder;

impl SpotlightQueryBuilder {
    pub const SUBSTRING_MINIMUM_LENGTH: usize = 3;

    pub fn terms(query: &str) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        let mut terms = Vec::new();
        let mut current = String::new();
        let flush = |current: &mut String,
                     seen: &mut std::collections::HashSet<String>,
                     terms: &mut Vec<String>| {
            if current.is_empty() {
                return;
            }
            if seen.insert(current.to_lowercase()) {
                terms.push(current.clone());
            }
            current.clear();
        };
        for ch in query.chars() {
            if ch.is_alphanumeric() {
                current.push(ch);
            } else {
                flush(&mut current, &mut seen, &mut terms);
            }
        }
        flush(&mut current, &mut seen, &mut terms);
        terms
    }

    pub fn escape(term: &str) -> String {
        let mut out = String::new();
        for ch in term.chars() {
            if matches!(ch, '\\' | '"' | '*' | '?') {
                out.push('\\');
            }
            out.push(ch);
        }
        out
    }

    pub fn query_string(query: &str, search_contents: bool) -> Option<String> {
        let terms = Self::terms(query);
        if terms.is_empty() {
            return None;
        }
        let clauses: Vec<String> = terms
            .iter()
            .map(|t| Self::clause(t, search_contents))
            .collect();
        Some(if clauses.len() == 1 {
            clauses[0].clone()
        } else {
            clauses.join(" && ")
        })
    }

    fn clause(term: &str, search_contents: bool) -> String {
        let escaped = Self::escape(term);
        let mut parts = Vec::new();
        if term.chars().count() >= Self::SUBSTRING_MINIMUM_LENGTH {
            let anywhere = format!("\"*{escaped}*\"cd");
            parts.push(format!("kMDItemDisplayName == {anywhere}"));
            parts.push(format!("kMDItemFSName == {anywhere}"));
        }
        let prefix = format!("\"{escaped}*\"cdw");
        parts.push(format!("kMDItemDisplayName == {prefix}"));
        parts.push(format!("kMDItemFSName == {prefix}"));
        if search_contents {
            parts.push(format!("kMDItemTextContent == \"{escaped}*\"cdw"));
        }
        format!("({})", parts.join(" || "))
    }
}

/// `mdfind` command line, matching how Raycast talks to Spotlight.
pub struct MdfindInvocation;

impl MdfindInvocation {
    pub const EXECUTABLE: &'static str = "/usr/bin/mdfind";

    pub fn arguments(
        query_string: Option<&str>,
        file_name: Option<&str>,
        only_in: &[String],
    ) -> Vec<String> {
        let mut args = Vec::new();
        for folder in only_in {
            args.push("-onlyin".into());
            args.push(folder.clone());
        }
        if let Some(name) = file_name {
            args.push("-name".into());
            args.push(name.to_string());
        }
        args.push("-0".into());
        if let Some(query) = query_string {
            args.push(query.to_string());
        } else if let Some(name) = file_name {
            args.push(name.to_string());
        }
        args
    }

    pub fn paths_from_null_terminated(data: &[u8], limit: usize) -> Vec<String> {
        if limit == 0 || data.is_empty() {
            return Vec::new();
        }
        let mut paths = Vec::new();
        let mut start = 0usize;
        while start < data.len() && paths.len() < limit {
            if let Some(rel) = data[start..].iter().position(|b| *b == 0) {
                let zero = start + rel;
                if zero > start {
                    if let Ok(path) = std::str::from_utf8(&data[start..zero]) {
                        if !path.is_empty() {
                            paths.push(path.to_string());
                        }
                    }
                }
                start = zero + 1;
            } else {
                if let Ok(path) = std::str::from_utf8(&data[start..]) {
                    if !path.is_empty() {
                        paths.push(path.to_string());
                    }
                }
                break;
            }
        }
        paths
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_scope_uses_onlyin() {
        assert_eq!(
            MdfindInvocation::arguments(
                Some("kMDItemFSName == \"*ember*\"cd"),
                None,
                &["/Users/ryan".into()]
            ),
            vec![
                "-onlyin",
                "/Users/ryan",
                "-0",
                "kMDItemFSName == \"*ember*\"cd"
            ]
        );
    }

    #[test]
    fn name_search() {
        assert_eq!(
            MdfindInvocation::arguments(None, Some("ember"), &["/Users/ryan".into()]),
            vec!["-onlyin", "/Users/ryan", "-name", "ember", "-0", "ember"]
        );
    }

    #[test]
    fn null_terminated_paths() {
        let data = b"/Users/ryan/a.pdf\0/Users/ryan/b.pdf\0/Users/ryan/c.pdf\0";
        assert_eq!(
            MdfindInvocation::paths_from_null_terminated(data, 2),
            vec!["/Users/ryan/a.pdf", "/Users/ryan/b.pdf"]
        );
    }
}
