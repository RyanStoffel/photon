//! Window management layout fractions (Accessibility applies them on macOS).

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowCommand {
    LeftHalf,
    RightHalf,
    TopHalf,
    BottomHalf,
    Maximize,
    AlmostMaximize,
    Center,
    FirstThird,
    CenterThird,
    LastThird,
    FirstTwoThirds,
    LastTwoThirds,
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

impl WindowCommand {
    pub fn matching(query: &str) -> Vec<Self> {
        let q = query.to_lowercase();
        Self::all()
            .into_iter()
            .filter(|cmd| cmd.title().to_lowercase().contains(&q) || q == "window")
            .collect()
    }

    fn all() -> Vec<Self> {
        vec![
            Self::LeftHalf,
            Self::RightHalf,
            Self::TopHalf,
            Self::BottomHalf,
            Self::Maximize,
            Self::AlmostMaximize,
            Self::Center,
            Self::FirstThird,
            Self::CenterThird,
            Self::LastThird,
            Self::FirstTwoThirds,
            Self::LastTwoThirds,
            Self::TopLeft,
            Self::TopRight,
            Self::BottomLeft,
            Self::BottomRight,
        ]
    }

    pub fn title(self) -> &'static str {
        match self {
            Self::LeftHalf => "Left Half",
            Self::RightHalf => "Right Half",
            Self::TopHalf => "Top Half",
            Self::BottomHalf => "Bottom Half",
            Self::Maximize => "Maximize",
            Self::AlmostMaximize => "Almost Maximize",
            Self::Center => "Center",
            Self::FirstThird => "First Third",
            Self::CenterThird => "Center Third",
            Self::LastThird => "Last Third",
            Self::FirstTwoThirds => "First Two Thirds",
            Self::LastTwoThirds => "Last Two Thirds",
            Self::TopLeft => "Top Left",
            Self::TopRight => "Top Right",
            Self::BottomLeft => "Bottom Left",
            Self::BottomRight => "Bottom Right",
        }
    }

    pub fn apply(self, visible: Rect) -> Rect {
        match self {
            Self::LeftHalf => Rect {
                x: visible.x,
                y: visible.y,
                width: visible.width / 2.0,
                height: visible.height,
            },
            Self::RightHalf => Rect {
                x: visible.x + visible.width / 2.0,
                y: visible.y,
                width: visible.width / 2.0,
                height: visible.height,
            },
            Self::TopHalf => Rect {
                x: visible.x,
                y: visible.y + visible.height / 2.0,
                width: visible.width,
                height: visible.height / 2.0,
            },
            Self::BottomHalf => Rect {
                x: visible.x,
                y: visible.y,
                width: visible.width,
                height: visible.height / 2.0,
            },
            Self::Maximize => visible,
            Self::AlmostMaximize => {
                let inset = 24.0;
                Rect {
                    x: visible.x + inset,
                    y: visible.y + inset,
                    width: visible.width - inset * 2.0,
                    height: visible.height - inset * 2.0,
                }
            }
            Self::Center => {
                let width = visible.width * 0.7;
                let height = visible.height * 0.7;
                Rect {
                    x: visible.x + (visible.width - width) / 2.0,
                    y: visible.y + (visible.height - height) / 2.0,
                    width,
                    height,
                }
            }
            Self::FirstThird => Rect {
                x: visible.x,
                y: visible.y,
                width: visible.width / 3.0,
                height: visible.height,
            },
            Self::CenterThird => Rect {
                x: visible.x + visible.width / 3.0,
                y: visible.y,
                width: visible.width / 3.0,
                height: visible.height,
            },
            Self::LastThird => Rect {
                x: visible.x + visible.width * 2.0 / 3.0,
                y: visible.y,
                width: visible.width / 3.0,
                height: visible.height,
            },
            Self::FirstTwoThirds => Rect {
                x: visible.x,
                y: visible.y,
                width: visible.width * 2.0 / 3.0,
                height: visible.height,
            },
            Self::LastTwoThirds => Rect {
                x: visible.x + visible.width / 3.0,
                y: visible.y,
                width: visible.width * 2.0 / 3.0,
                height: visible.height,
            },
            Self::TopLeft => Rect {
                x: visible.x,
                y: visible.y + visible.height / 2.0,
                width: visible.width / 2.0,
                height: visible.height / 2.0,
            },
            Self::TopRight => Rect {
                x: visible.x + visible.width / 2.0,
                y: visible.y + visible.height / 2.0,
                width: visible.width / 2.0,
                height: visible.height / 2.0,
            },
            Self::BottomLeft => Rect {
                x: visible.x,
                y: visible.y,
                width: visible.width / 2.0,
                height: visible.height / 2.0,
            },
            Self::BottomRight => Rect {
                x: visible.x + visible.width / 2.0,
                y: visible.y,
                width: visible.width / 2.0,
                height: visible.height / 2.0,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn halves_split_visible_frame() {
        let vis = Rect {
            x: 0.0,
            y: 0.0,
            width: 1000.0,
            height: 800.0,
        };
        let left = WindowCommand::LeftHalf.apply(vis);
        assert_eq!(left.width, 500.0);
        let max = WindowCommand::Maximize.apply(vis);
        assert_eq!(max.width, 1000.0);
    }
}
