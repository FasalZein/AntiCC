package handlers

import (
	"encoding/json"
	"io"
	"net/http"

	"cliproxy-middleware/internal/config"
)

// TokenCountRequest represents the Anthropic token count request
type TokenCountRequest struct {
	Model    string          `json:"model"`
	Messages json.RawMessage `json:"messages"`
	System   json.RawMessage `json:"system,omitempty"`
	Tools    json.RawMessage `json:"tools,omitempty"`
}

// TokenCountResponse represents the Anthropic token count response
type TokenCountResponse struct {
	InputTokens int `json:"input_tokens"`
}

// TokenCount handles /v1/messages/count_tokens with local estimation
func TokenCount(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, `{"error":{"message":"Method not allowed","type":"invalid_request_error"}}`, http.StatusMethodNotAllowed)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, `{"error":{"message":"Failed to read request body","type":"invalid_request_error"}}`, http.StatusBadRequest)
			return
		}
		defer r.Body.Close()

		var req TokenCountRequest
		if err := json.Unmarshal(body, &req); err != nil {
			http.Error(w, `{"error":{"message":"Invalid JSON","type":"invalid_request_error"}}`, http.StatusBadRequest)
			return
		}

		// Estimate tokens from content
		totalChars := len(string(req.Messages)) + len(string(req.System)) + len(string(req.Tools))
		estimatedTokens := int(float64(totalChars) / cfg.TokenMultiplier)
		if totalChars > 0 && estimatedTokens == 0 {
			estimatedTokens = 1
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(TokenCountResponse{InputTokens: estimatedTokens})
	}
}

// Health returns a simple health check response
func Health() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","middleware":"cliproxy-middleware"}`))
	}
}
