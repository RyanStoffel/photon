use serde::{Deserialize, Serialize};

/// Visible area of a display in AppKit coordinates (origin bottom-left).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScreenVisibleFrame {
    pub min_x: f64,
    pub min_y: f64,
    pub width: f64,
    pub height: f64,
}

impl ScreenVisibleFrame {
    pub fn mid_x(self) -> f64 {
        self.min_x + self.width / 2.0
    }

    pub fn max_y(self) -> f64 {
        self.min_y + self.height
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PanelSize {
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PanelOrigin {
    pub x: f64,
    pub y: f64,
}

/// User-customized launcher placement. `origin_x` is ignored when centered horizontally.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct LauncherStoredPosition {
    pub origin_y: f64,
    pub is_horizontally_centered: bool,
    pub origin_x: f64,
}

pub struct LauncherPosition;

impl LauncherPosition {
    pub fn default_origin(panel_size: PanelSize, visible: ScreenVisibleFrame) -> PanelOrigin {
        let top = (visible.min_y + visible.height * 0.74).min(visible.max_y() - 8.0);
        PanelOrigin {
            x: visible.mid_x() - panel_size.width / 2.0,
            y: top - panel_size.height,
        }
    }

    pub fn origin(
        panel_size: PanelSize,
        visible: ScreenVisibleFrame,
        stored: Option<LauncherStoredPosition>,
    ) -> PanelOrigin {
        let Some(stored) = stored else {
            return Self::default_origin(panel_size, visible);
        };
        let x = if stored.is_horizontally_centered {
            visible.mid_x() - panel_size.width / 2.0
        } else {
            stored.origin_x
        };
        Self::clamped_origin(
            PanelOrigin {
                x,
                y: stored.origin_y,
            },
            panel_size,
            visible,
        )
    }

    pub fn clamped_origin(
        origin: PanelOrigin,
        panel_size: PanelSize,
        visible: ScreenVisibleFrame,
    ) -> PanelOrigin {
        let min_x = visible.min_x;
        let max_x = visible.min_x + visible.width - panel_size.width;
        let min_y = visible.min_y;
        let max_y = visible.max_y() - panel_size.height;
        PanelOrigin {
            x: origin.x.clamp(min_x.min(max_x), min_x.max(max_x)),
            y: origin.y.clamp(min_y.min(max_y), min_y.max(max_y)),
        }
    }

    pub fn snap_guide_x_positions(visible: ScreenVisibleFrame, panel_width: f64) -> (f64, f64) {
        (
            visible.mid_x() - panel_width / 2.0,
            visible.mid_x() + panel_width / 2.0,
        )
    }

    pub fn resolve_horizontal_snap(
        panel_mid_x: f64,
        panel_width: f64,
        visible: ScreenVisibleFrame,
    ) -> (f64, bool) {
        let (left, right) = Self::snap_guide_x_positions(visible, panel_width);
        if panel_mid_x >= left && panel_mid_x <= right {
            (visible.mid_x() - panel_width / 2.0, true)
        } else {
            (panel_mid_x - panel_width / 2.0, false)
        }
    }

    pub fn live_drag_origin(
        initial_origin: PanelOrigin,
        start_mouse: PanelOrigin,
        current_mouse: PanelOrigin,
        panel_width: f64,
        visible: ScreenVisibleFrame,
    ) -> PanelOrigin {
        let raw = PanelOrigin {
            x: initial_origin.x + (current_mouse.x - start_mouse.x),
            y: initial_origin.y + (current_mouse.y - start_mouse.y),
        };
        let (origin_x, _) =
            Self::resolve_horizontal_snap(raw.x + panel_width / 2.0, panel_width, visible);
        PanelOrigin {
            x: origin_x,
            y: raw.y,
        }
    }

    pub fn stored_position(
        origin: PanelOrigin,
        panel_width: f64,
        visible: ScreenVisibleFrame,
    ) -> LauncherStoredPosition {
        let mid_x = origin.x + panel_width / 2.0;
        let (origin_x, centered) = Self::resolve_horizontal_snap(mid_x, panel_width, visible);
        LauncherStoredPosition {
            origin_y: origin.y,
            is_horizontally_centered: centered,
            origin_x,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screen() -> ScreenVisibleFrame {
        ScreenVisibleFrame {
            min_x: 0.0,
            min_y: 0.0,
            width: 1440.0,
            height: 900.0,
        }
    }

    #[test]
    fn default_is_centered_near_three_quarters() {
        let origin = LauncherPosition::default_origin(
            PanelSize {
                width: 740.0,
                height: 89.0,
            },
            screen(),
        );
        assert!((origin.x - (1440.0 - 740.0) / 2.0).abs() < 0.01);
        let top = origin.y + 89.0;
        assert!((top - 900.0 * 0.74).abs() < 1.0);
    }

    #[test]
    fn live_snap_keeps_midpoint_between_guides() {
        let visible = screen();
        let width = 740.0;
        let start = LauncherPosition::default_origin(
            PanelSize {
                width,
                height: 89.0,
            },
            visible,
        );
        let dragged = LauncherPosition::live_drag_origin(
            start,
            PanelOrigin { x: 100.0, y: 100.0 },
            PanelOrigin { x: 140.0, y: 80.0 },
            width,
            visible,
        );
        let mid = dragged.x + width / 2.0;
        let (left, right) = LauncherPosition::snap_guide_x_positions(visible, width);
        assert!(mid >= left && mid <= right);
        assert!((dragged.y - (start.y - 20.0)).abs() < 0.01);
    }
}
