#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandIcon {
    FilePath(String),
    Application { bundle_id: String, path: String },
    Symbol(&'static str),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Command {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub keywords: Vec<String>,
    pub provider_id: String,
    pub icon: Option<CommandIcon>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RankedCommand {
    pub command: Command,
    pub score: f64,
}

impl RankedCommand {
    pub fn id(&self) -> &str {
        &self.command.id
    }
}
