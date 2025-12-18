package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

// Config holds the middleware configuration
type Config struct {
	Port            int
	UpstreamURL     string
	APIKey          string
	Debug           bool
	LogRequests     bool
	TokenMultiplier float64 // Rough multiplier for token estimation (chars / multiplier = tokens)
}

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

func main() {
	cfg := Config{}

	flag.IntVar(&cfg.Port, "port", 8318, "Port to listen on")
	flag.StringVar(&cfg.UpstreamURL, "upstream", "http://127.0.0.1:8317", "CLIProxyAPI upstream URL")
	flag.StringVar(&cfg.APIKey, "api-key", "", "API key for authentication (optional, passes through if not set)")
	flag.BoolVar(&cfg.Debug, "debug", false, "Enable debug logging")
	flag.BoolVar(&cfg.LogRequests, "log-requests", false, "Log all requests")
	flag.Float64Var(&cfg.TokenMultiplier, "token-multiplier", 4.0, "Character to token ratio (default: 4 chars = 1 token)")
	flag.Parse()

	// Check for environment variables
	if cfg.UpstreamURL == "http://127.0.0.1:8317" {
		if envURL := os.Getenv("CLIPROXY_UPSTREAM_URL"); envURL != "" {
			cfg.UpstreamURL = envURL
		}
	}
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("CLIPROXY_API_KEY")
	}

	upstream, err := url.Parse(cfg.UpstreamURL)
	if err != nil {
		log.Fatalf("Invalid upstream URL: %v", err)
	}

	// Create reverse proxy
	proxy := httputil.NewSingleHostReverseProxy(upstream)

	// Custom transport for logging
	if cfg.Debug {
		proxy.Transport = &loggingTransport{http.DefaultTransport}
	}

	// Modify the director to handle streaming properly
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		// Ensure we're not buffering for streaming
		req.Header.Del("Accept-Encoding")
	}

	// Handle streaming responses properly
	proxy.ModifyResponse = func(resp *http.Response) error {
		// For SSE streams, ensure proper headers
		if strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream") {
			resp.Header.Del("Content-Length")
		}
		return nil
	}

	// Setup HTTP handlers
	mux := http.NewServeMux()

	// Token counting endpoint - handle locally
	mux.HandleFunc("/v1/messages/count_tokens", func(w http.ResponseWriter, r *http.Request) {
		handleTokenCount(w, r, cfg)
	})

	// Health check
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","middleware":"cliproxy-middleware"}`))
	})

	// All other requests - proxy to upstream
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if cfg.LogRequests {
			log.Printf("[%s] %s %s", r.Method, r.URL.Path, r.RemoteAddr)
		}

		// For streaming, we need to flush immediately
		if flusher, ok := w.(http.Flusher); ok {
			proxy.ServeHTTP(&flushWriter{w, flusher}, r)
		} else {
			proxy.ServeHTTP(w, r)
		}
	})

	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("🚀 CLIProxy Middleware starting on http://127.0.0.1%s", addr)
	log.Printf("   Upstream: %s", cfg.UpstreamURL)
	log.Printf("   Token counting: enabled (local estimation)")
	if cfg.Debug {
		log.Printf("   Debug mode: enabled")
	}

	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  5 * time.Minute,
		WriteTimeout: 10 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

// handleTokenCount estimates token count locally
func handleTokenCount(w http.ResponseWriter, r *http.Request, cfg Config) {
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

	// Estimate tokens from the request content
	totalChars := 0

	// Count messages
	if len(req.Messages) > 0 {
		totalChars += len(string(req.Messages))
	}

	// Count system prompt
	if len(req.System) > 0 {
		totalChars += len(string(req.System))
	}

	// Count tools
	if len(req.Tools) > 0 {
		totalChars += len(string(req.Tools))
	}

	// Estimate tokens (rough approximation: ~4 chars per token for English)
	estimatedTokens := int(float64(totalChars) / cfg.TokenMultiplier)

	// Ensure minimum of 1 token if there's any content
	if totalChars > 0 && estimatedTokens == 0 {
		estimatedTokens = 1
	}

	if cfg.Debug {
		log.Printf("[token_count] chars=%d estimated_tokens=%d model=%s", totalChars, estimatedTokens, req.Model)
	}

	resp := TokenCountResponse{
		InputTokens: estimatedTokens,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// flushWriter wraps ResponseWriter to flush after each write (for SSE)
type flushWriter struct {
	http.ResponseWriter
	flusher http.Flusher
}

func (fw *flushWriter) Write(p []byte) (int, error) {
	n, err := fw.ResponseWriter.Write(p)
	fw.flusher.Flush()
	return n, err
}

// loggingTransport logs HTTP requests/responses for debugging
type loggingTransport struct {
	transport http.RoundTripper
}

func (t *loggingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	log.Printf("[DEBUG] → %s %s", req.Method, req.URL.String())

	// Log request body for non-streaming
	if req.Body != nil && req.ContentLength > 0 && req.ContentLength < 10000 {
		body, _ := io.ReadAll(req.Body)
		req.Body = io.NopCloser(bytes.NewReader(body))
		log.Printf("[DEBUG] Request body: %s", truncate(string(body), 500))
	}

	resp, err := t.transport.RoundTrip(req)
	if err != nil {
		log.Printf("[DEBUG] ← Error: %v", err)
		return resp, err
	}

	log.Printf("[DEBUG] ← %d %s", resp.StatusCode, resp.Status)
	return resp, err
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
