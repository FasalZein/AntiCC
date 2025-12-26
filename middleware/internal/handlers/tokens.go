package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"time"

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

// httpClient is a shared client with connection pooling for token counting
var tokenCountClient = &http.Client{
	Timeout: 30 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        10,
		MaxIdleConnsPerHost: 5,
		IdleConnTimeout:     90 * time.Second,
	},
}

// TokenCount handles /v1/messages/count_tokens by forwarding to upstream
// Falls back to local estimation if upstream fails
func TokenCount(cfg *config.Config, proxy *httputil.ReverseProxy) http.HandlerFunc {
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
		r.Body.Close()

		// Parse request for model mapping
		var rawRequest map[string]json.RawMessage
		if err := json.Unmarshal(body, &rawRequest); err != nil {
			http.Error(w, `{"error":{"message":"Invalid JSON","type":"invalid_request_error"}}`, http.StatusBadRequest)
			return
		}

		// Map model name if present
		if modelRaw, hasModel := rawRequest["model"]; hasModel {
			var model string
			if err := json.Unmarshal(modelRaw, &model); err == nil {
				mappedModel := config.MapModel(model)
				if mappedModel != model {
					if cfg.Debug {
						log.Printf("[token_count] model mapped: %s -> %s", model, mappedModel)
					}
					newModelJSON, _ := json.Marshal(mappedModel)
					rawRequest["model"] = newModelJSON
					body, _ = json.Marshal(rawRequest)
				}
			}
		}

		// Try to forward to upstream for accurate token counting
		upstreamURL := fmt.Sprintf("%s/v1/messages/count_tokens", cfg.UpstreamURL)

		req, err := http.NewRequest("POST", upstreamURL, bytes.NewReader(body))
		if err != nil {
			if cfg.Debug {
				log.Printf("[token_count] failed to create request: %v, using fallback", err)
			}
			sendFallbackTokenCount(w, body, cfg)
			return
		}

		// Copy headers from original request
		req.Header.Set("Content-Type", "application/json")
		if auth := r.Header.Get("Authorization"); auth != "" {
			req.Header.Set("Authorization", auth)
		} else if r.Header.Get("x-api-key") != "" {
			req.Header.Set("x-api-key", r.Header.Get("x-api-key"))
		} else if cfg.APIKey != "" {
			req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
		}

		// Forward anthropic-version header if present
		if ver := r.Header.Get("anthropic-version"); ver != "" {
			req.Header.Set("anthropic-version", ver)
		}

		resp, err := tokenCountClient.Do(req)
		if err != nil {
			if cfg.Debug {
				log.Printf("[token_count] upstream request failed: %v, using fallback", err)
			}
			sendFallbackTokenCount(w, body, cfg)
			return
		}
		defer resp.Body.Close()

		// If upstream returns non-2xx, use fallback
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			respBody, _ := io.ReadAll(resp.Body)
			if cfg.Debug {
				log.Printf("[token_count] upstream returned %d: %s, using fallback", resp.StatusCode, string(respBody))
			}
			sendFallbackTokenCount(w, body, cfg)
			return
		}

		// Forward upstream response
		respBody, err := io.ReadAll(resp.Body)
		if err != nil {
			if cfg.Debug {
				log.Printf("[token_count] failed to read upstream response: %v, using fallback", err)
			}
			sendFallbackTokenCount(w, body, cfg)
			return
		}

		if cfg.Debug {
			log.Printf("[token_count] upstream returned: %s", string(respBody))
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resp.StatusCode)
		w.Write(respBody)
	}
}

// sendFallbackTokenCount sends an estimated token count when upstream is unavailable
func sendFallbackTokenCount(w http.ResponseWriter, body []byte, cfg *config.Config) {
	var req TokenCountRequest
	if err := json.Unmarshal(body, &req); err != nil {
		// If we can't parse, just estimate based on raw body size
		estimatedTokens := len(body) / 4
		if estimatedTokens == 0 {
			estimatedTokens = 1
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(TokenCountResponse{InputTokens: estimatedTokens})
		return
	}

	// Estimate tokens from content (roughly 4 characters per token)
	totalChars := len(string(req.Messages)) + len(string(req.System)) + len(string(req.Tools))
	estimatedTokens := int(float64(totalChars) / cfg.TokenMultiplier)
	if totalChars > 0 && estimatedTokens == 0 {
		estimatedTokens = 1
	}

	if cfg.Debug {
		log.Printf("[token_count] fallback estimate: %d chars -> %d tokens", totalChars, estimatedTokens)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(TokenCountResponse{InputTokens: estimatedTokens})
}

// Health returns a simple health check response
func Health() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","middleware":"cliproxy-middleware"}`))
	}
}
