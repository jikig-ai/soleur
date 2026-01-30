//! Shared marker constants for structured output parsing
//!
//! This module defines the markers used for parsing structured data from agent responses.
//! By defining them in one place, we ensure consistency between the prompts that instruct
//! agents to emit markers and the code that parses them.

/// Regex pattern for matching decision markers in agent responses
pub const DECISION_MARKER_REGEX: &str = r"\[DECISION:\s*([^\]]+)\]";

/// Instruction text for decision markers (used in agent prompts)
pub const DECISION_MARKER_INSTRUCTION: &str = "[DECISION: brief description of the decision]";

#[cfg(test)]
mod tests {
    use super::*;
    use regex::Regex;

    #[test]
    fn test_decision_marker_regex_is_valid() {
        // Ensure the regex compiles successfully
        let re = Regex::new(DECISION_MARKER_REGEX);
        assert!(re.is_ok(), "Decision marker regex should be valid");
    }

    #[test]
    fn test_decision_marker_matches_instruction() {
        // Ensure the regex matches the instruction format
        let re = Regex::new(DECISION_MARKER_REGEX).unwrap();
        let sample = "Here's a decision: [DECISION: Focus on enterprise customers]";
        let caps = re.captures(sample);
        assert!(caps.is_some(), "Regex should match sample decision");
        assert_eq!(caps.unwrap()[1].trim(), "Focus on enterprise customers");
    }

    #[test]
    fn test_decision_marker_with_whitespace() {
        let re = Regex::new(DECISION_MARKER_REGEX).unwrap();
        let sample = "[DECISION:   no leading space trimmed   ]";
        let caps = re.captures(sample);
        assert!(caps.is_some());
        assert_eq!(caps.unwrap()[1].trim(), "no leading space trimmed");
    }
}
