//! Fixed metrics of the launcher panel. Heights are derived here so the GPUI
//! window and the rendered content always agree on the panel size.

use serde::{Deserialize, Serialize};

/// User-selectable launcher panel width.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum LauncherPanelWidth {
    Compact,
    #[default]
    Regular,
    Wide,
}

impl LauncherPanelWidth {
    pub fn title(self) -> &'static str {
        match self {
            Self::Compact => "Compact",
            Self::Regular => "Regular",
            Self::Wide => "Wide",
        }
    }

    pub fn points(self) -> f64 {
        match self {
            Self::Compact => 620.0,
            Self::Regular => 740.0,
            Self::Wide => 860.0,
        }
    }
}

/// What the launcher panel shows below the search field.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Content {
    /// Empty query in compact mode: search field and footer only.
    SearchOnly,
    /// The command list. `0` rows still shows one line (indexing or no results).
    Rows {
        count: usize,
        shows_calculator_hero: bool,
    },
    /// A feature view with its own layout (clipboard history, file search).
    FullHeight,
}

/// Fixed metrics of the launcher panel.
pub struct LauncherLayout;

impl LauncherLayout {
    pub const SEARCH_FIELD_HEIGHT: f64 = 56.0;
    pub const FOOTER_HEIGHT: f64 = 32.0;
    pub const ROW_HEIGHT: f64 = 40.0;
    pub const LIST_INSET: f64 = 6.0;
    pub const MAX_VISIBLE_ROWS: usize = 8;
    pub const SUGGESTION_COUNT: usize = 8;
    pub const HAIRLINE: f64 = 1.0;
    pub const CORNER_RADIUS: f64 = 12.0;
    pub const ICON_SIZE: f64 = 28.0;
    pub const CALCULATOR_SECTION_SPACING: f64 = 8.0;
    pub const CALCULATOR_CARD_HEIGHT: f64 = 108.0;
    pub const CALCULATOR_SECTION_HEADER_HEIGHT: f64 = 18.0;

    pub fn list_height(row_count: usize, shows_calculator_hero: bool) -> f64 {
        let hero_height = if shows_calculator_hero {
            Self::CALCULATOR_SECTION_HEADER_HEIGHT
                + Self::CALCULATOR_SECTION_SPACING
                + Self::CALCULATOR_CARD_HEIGHT
                + Self::LIST_INSET
        } else {
            0.0
        };
        let data_rows = if shows_calculator_hero {
            row_count.saturating_sub(1)
        } else {
            row_count
        };
        if shows_calculator_hero && data_rows == 0 {
            return hero_height;
        }
        let visible = data_rows.max(1).min(Self::MAX_VISIBLE_ROWS);
        hero_height + visible as f64 * Self::ROW_HEIGHT + 2.0 * Self::LIST_INSET
    }

    pub fn compact_height() -> f64 {
        Self::SEARCH_FIELD_HEIGHT + Self::HAIRLINE + Self::FOOTER_HEIGHT
    }

    pub fn max_height() -> f64 {
        Self::height_for(Content::Rows {
            count: Self::MAX_VISIBLE_ROWS,
            shows_calculator_hero: false,
        })
    }

    pub fn height_for(content: Content) -> f64 {
        match content {
            Content::SearchOnly => Self::compact_height(),
            Content::Rows {
                count,
                shows_calculator_hero,
            } => {
                Self::SEARCH_FIELD_HEIGHT
                    + Self::HAIRLINE
                    + Self::list_height(count, shows_calculator_hero)
                    + Self::HAIRLINE
                    + Self::FOOTER_HEIGHT
            }
            Content::FullHeight => Self::max_height(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_is_search_plus_hairline_plus_footer() {
        assert_eq!(LauncherLayout::compact_height(), 56.0 + 1.0 + 32.0);
        assert_eq!(
            LauncherLayout::height_for(Content::SearchOnly),
            LauncherLayout::compact_height()
        );
    }

    #[test]
    fn empty_clipboard_and_files_use_compact_height() {
        assert_eq!(
            LauncherLayout::height_for(Content::SearchOnly),
            LauncherLayout::compact_height()
        );
        assert!(LauncherLayout::compact_height() < 100.0);
        assert!(LauncherLayout::max_height() > LauncherLayout::compact_height() * 3.0);
    }

    #[test]
    fn panel_widths() {
        assert_eq!(LauncherPanelWidth::Compact.points(), 620.0);
        assert_eq!(LauncherPanelWidth::Regular.points(), 740.0);
        assert_eq!(LauncherPanelWidth::Wide.points(), 860.0);
    }
}
