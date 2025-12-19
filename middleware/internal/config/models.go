package config

import "strings"

// DefaultModelMappings maps standard Claude model names to Antigravity equivalents
// Roo Code uses these exact model names:
// - claude-sonnet-4-5-20250929
// - claude-opus-4-5-20251101
// - claude-haiku-4-5-20251001
//
// Available Antigravity models:
// - gemini-claude-opus-4-5-thinking
// - gemini-claude-sonnet-4-5-thinking
// - gemini-claude-sonnet-4-5
// - gemini-3-flash
// - gemini-3-pro-high
// - gemini-3-pro-low
var DefaultModelMappings = map[string]string{
	// Roo Code exact model names
	"claude-opus-4-5-20251101":   "gemini-claude-opus-4-5-thinking",
	"claude-sonnet-4-5-20250929": "gemini-claude-sonnet-4-5-thinking",
	"claude-haiku-4-5-20251001":  "gemini-3-flash", // Haiku -> Gemini 3 Flash
}

// Model prefix mappings for unknown versions
var prefixMappings = []struct {
	prefix string
	target string
}{
	// Order matters - more specific prefixes first
	{"claude-opus", "gemini-claude-opus-4-5-thinking"},
	{"claude-sonnet", "gemini-claude-sonnet-4-5-thinking"},
	{"claude-haiku", "gemini-3-flash"},
	{"gpt-4", "gemini-claude-sonnet-4-5-thinking"},
	{"gpt-3", "gemini-3-flash"},
}

// MapModel translates a model name to its Antigravity equivalent
// Returns the original model if no mapping exists
func MapModel(model string) string {
	// First check exact match
	if mapped, ok := DefaultModelMappings[model]; ok {
		return mapped
	}

	// Then check prefix matches for unknown versions
	for _, pm := range prefixMappings {
		if strings.HasPrefix(model, pm.prefix) {
			return pm.target
		}
	}

	return model
}
