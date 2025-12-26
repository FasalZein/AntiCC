package handlers

import (
	"encoding/json"
	"log"
	"sync"
	"sync/atomic"
	"time"
)

// UsageStats tracks token usage across sessions
type UsageStats struct {
	mu              sync.RWMutex
	InputTokens     atomic.Int64
	OutputTokens    atomic.Int64
	CacheCreation   atomic.Int64
	CacheRead       atomic.Int64
	TotalRequests   atomic.Int64
	SessionStart    time.Time
	LastRequestTime time.Time
}

// Global usage tracker
var globalUsage = &UsageStats{
	SessionStart: time.Now(),
}

// AnthropicUsage represents the usage field in Anthropic API responses
type AnthropicUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens,omitempty"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens,omitempty"`
}

// StreamDelta represents a streaming event that may contain usage
type StreamDelta struct {
	Type  string          `json:"type"`
	Usage *AnthropicUsage `json:"usage,omitempty"`
}

// TrackUsageFromResponse extracts and tracks usage from an API response body
// Works for both streaming and non-streaming responses
func TrackUsageFromResponse(body []byte, isStreaming bool, debug bool) {
	if isStreaming {
		trackStreamingUsage(body, debug)
	} else {
		trackNonStreamingUsage(body, debug)
	}
}

// trackNonStreamingUsage handles regular JSON responses
func trackNonStreamingUsage(body []byte, debug bool) {
	var response struct {
		Usage *AnthropicUsage `json:"usage"`
	}

	if err := json.Unmarshal(body, &response); err != nil {
		return
	}

	if response.Usage != nil {
		addUsage(response.Usage, debug)
	}
}

// trackStreamingUsage handles SSE streaming responses
// The final message_delta event contains the usage
func trackStreamingUsage(body []byte, debug bool) {
	// Look for usage in the body (it appears in message_delta events)
	// SSE format: data: {"type":"message_delta","usage":{...}}

	var delta StreamDelta
	if err := json.Unmarshal(body, &delta); err != nil {
		return
	}

	if delta.Usage != nil {
		addUsage(delta.Usage, debug)
	}
}

// addUsage adds the given usage to global stats
func addUsage(usage *AnthropicUsage, debug bool) {
	globalUsage.mu.Lock()
	globalUsage.LastRequestTime = time.Now()
	globalUsage.mu.Unlock()

	globalUsage.TotalRequests.Add(1)

	if usage.InputTokens > 0 {
		globalUsage.InputTokens.Add(int64(usage.InputTokens))
	}
	if usage.OutputTokens > 0 {
		globalUsage.OutputTokens.Add(int64(usage.OutputTokens))
	}
	if usage.CacheCreationInputTokens > 0 {
		globalUsage.CacheCreation.Add(int64(usage.CacheCreationInputTokens))
	}
	if usage.CacheReadInputTokens > 0 {
		globalUsage.CacheRead.Add(int64(usage.CacheReadInputTokens))
	}

	if debug {
		log.Printf("[usage] +%d input, +%d output (total: %d in / %d out)",
			usage.InputTokens, usage.OutputTokens,
			globalUsage.InputTokens.Load(), globalUsage.OutputTokens.Load())
	}
}

// GetUsageStats returns current usage statistics
func GetUsageStats() map[string]interface{} {
	globalUsage.mu.RLock()
	lastRequest := globalUsage.LastRequestTime
	sessionStart := globalUsage.SessionStart
	globalUsage.mu.RUnlock()

	stats := map[string]interface{}{
		"input_tokens":                globalUsage.InputTokens.Load(),
		"output_tokens":               globalUsage.OutputTokens.Load(),
		"cache_creation_input_tokens": globalUsage.CacheCreation.Load(),
		"cache_read_input_tokens":     globalUsage.CacheRead.Load(),
		"total_requests":              globalUsage.TotalRequests.Load(),
		"session_start":               sessionStart.Format(time.RFC3339),
		"session_duration":            time.Since(sessionStart).Round(time.Second).String(),
	}

	if !lastRequest.IsZero() {
		stats["last_request"] = lastRequest.Format(time.RFC3339)
	}

	return stats
}

// ResetUsageStats resets the usage counters (for new sessions)
func ResetUsageStats() {
	globalUsage.InputTokens.Store(0)
	globalUsage.OutputTokens.Store(0)
	globalUsage.CacheCreation.Store(0)
	globalUsage.CacheRead.Store(0)
	globalUsage.TotalRequests.Store(0)

	globalUsage.mu.Lock()
	globalUsage.SessionStart = time.Now()
	globalUsage.LastRequestTime = time.Time{}
	globalUsage.mu.Unlock()
}
