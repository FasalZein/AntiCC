package main

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"time"

	"cliproxy-middleware/internal/config"
	"cliproxy-middleware/internal/handlers"
	"cliproxy-middleware/internal/proxy"
)

func main() {
	cfg := config.Load()

	// Create reverse proxy
	reverseProxy, err := proxy.New(cfg)
	if err != nil {
		log.Fatalf("Failed to create proxy: %v", err)
	}

	// Setup routes
	mux := http.NewServeMux()
	// Anthropic-style endpoints
	mux.HandleFunc("/v1/messages/count_tokens", handlers.TokenCount(cfg))
	mux.HandleFunc("/v1/messages", handlers.Messages(cfg, reverseProxy))
	// OpenAI-style endpoints
	mux.HandleFunc("/v1/chat/completions", handlers.ChatCompletions(cfg, reverseProxy))
	// Health and default
	mux.HandleFunc("/health", handlers.Health())
	mux.HandleFunc("/", defaultHandler(cfg, reverseProxy))

	// Start server
	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("🚀 CLIProxy Middleware starting on http://127.0.0.1%s", addr)
	log.Printf("   Upstream: %s", cfg.UpstreamURL)
	log.Printf("   Endpoints: /v1/messages (Anthropic), /v1/chat/completions (OpenAI)")
	log.Printf("   Token counting: enabled (local estimation for Anthropic)")
	log.Printf("   Schema normalization: enabled (Gemini compatibility)")
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

func defaultHandler(cfg *config.Config, reverseProxy *httputil.ReverseProxy) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cfg.LogRequests {
			log.Printf("[%s] %s %s", r.Method, r.URL.Path, r.RemoteAddr)
		}
		if flusher, ok := w.(http.Flusher); ok {
			reverseProxy.ServeHTTP(&flushWriter{w, flusher}, r)
		} else {
			reverseProxy.ServeHTTP(w, r)
		}
	}
}

type flushWriter struct {
	http.ResponseWriter
	flusher http.Flusher
}

func (fw *flushWriter) Write(p []byte) (int, error) {
	n, err := fw.ResponseWriter.Write(p)
	fw.flusher.Flush()
	return n, err
}
