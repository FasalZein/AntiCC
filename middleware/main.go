package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"cliproxy-middleware/internal/config"
	"cliproxy-middleware/internal/handlers"
	"cliproxy-middleware/internal/proxy"
)

// Server wraps the HTTP server with health tracking
type Server struct {
	httpServer     *http.Server
	proxy          *httputil.ReverseProxy
	cfg            *config.Config
	healthy        atomic.Bool
	upstreamHealth atomic.Bool
	startTime      time.Time
	requestCount   atomic.Int64
}

func main() {
	cfg := config.Load()

	// Create reverse proxy with connection pooling
	reverseProxy, err := proxy.NewWithPool(cfg)
	if err != nil {
		log.Fatalf("Failed to create proxy: %v", err)
	}

	srv := &Server{
		proxy:     reverseProxy,
		cfg:       cfg,
		startTime: time.Now(),
	}
	srv.healthy.Store(true)
	srv.upstreamHealth.Store(false)

	// Setup routes
	mux := http.NewServeMux()

	// Anthropic-style endpoints
	mux.HandleFunc("/v1/messages/count_tokens", srv.wrapHandler(handlers.TokenCount(cfg, reverseProxy)))
	mux.HandleFunc("/v1/messages", srv.wrapHandler(handlers.Messages(cfg, reverseProxy)))

	// OpenAI-style endpoints
	mux.HandleFunc("/v1/chat/completions", srv.wrapHandler(handlers.ChatCompletions(cfg, reverseProxy)))

	// Health and metrics
	mux.HandleFunc("/health", srv.healthHandler())
	mux.HandleFunc("/health/live", srv.livenessHandler())
	mux.HandleFunc("/health/ready", srv.readinessHandler())
	mux.HandleFunc("/metrics", srv.metricsHandler())
	mux.HandleFunc("/usage", srv.usageHandler())

	// Default handler
	mux.HandleFunc("/", srv.defaultHandler())

	// Configure server with optimized timeouts
	addr := fmt.Sprintf(":%d", cfg.Port)
	srv.httpServer = &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadTimeout:       30 * time.Second,
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      10 * time.Minute, // Long for streaming responses
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1MB
	}

	// Start upstream health checker
	go srv.healthChecker()

	// Start server in goroutine
	go func() {
		log.Printf("🚀 CLIProxy Middleware starting on http://127.0.0.1%s", addr)
		log.Printf("   Upstream: %s", cfg.UpstreamURL)
		log.Printf("   Endpoints: /v1/messages (Anthropic), /v1/chat/completions (OpenAI)")
		log.Printf("   Features: token counting, schema normalization, usage tracking")
		log.Printf("   Health: /health, /metrics, /usage")
		if cfg.Debug {
			log.Printf("   Debug mode: enabled")
		}

		if err := srv.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal
	srv.waitForShutdown()
}

// wrapHandler adds request counting and logging
func (s *Server) wrapHandler(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s.requestCount.Add(1)
		if s.cfg.LogRequests {
			log.Printf("[%s] %s %s", r.Method, r.URL.Path, r.RemoteAddr)
		}
		h(w, r)
	}
}

// healthHandler returns basic health status
func (s *Server) healthHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		uptime := time.Since(s.startTime).Round(time.Second)
		status := "ok"
		httpStatus := http.StatusOK

		if !s.healthy.Load() {
			status = "degraded"
			httpStatus = http.StatusServiceUnavailable
		}

		w.WriteHeader(httpStatus)
		fmt.Fprintf(w, `{"status":"%s","uptime":"%s","requests":%d,"upstream_healthy":%t}`,
			status, uptime, s.requestCount.Load(), s.upstreamHealth.Load())
	}
}

// livenessHandler for k8s liveness probe - is the process alive?
func (s *Server) livenessHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"alive"}`))
	}
}

// readinessHandler for k8s readiness probe - can we serve traffic?
func (s *Server) readinessHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		if !s.upstreamHealth.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"status":"not_ready","reason":"upstream_unavailable"}`))
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ready"}`))
	}
}

// metricsHandler returns prometheus-style metrics
func (s *Server) metricsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")

		uptime := time.Since(s.startTime).Seconds()
		upstreamUp := 0
		if s.upstreamHealth.Load() {
			upstreamUp = 1
		}

		fmt.Fprintf(w, "# HELP cliproxy_uptime_seconds Time since middleware started\n")
		fmt.Fprintf(w, "# TYPE cliproxy_uptime_seconds gauge\n")
		fmt.Fprintf(w, "cliproxy_uptime_seconds %.2f\n", uptime)
		fmt.Fprintf(w, "# HELP cliproxy_requests_total Total requests handled\n")
		fmt.Fprintf(w, "# TYPE cliproxy_requests_total counter\n")
		fmt.Fprintf(w, "cliproxy_requests_total %d\n", s.requestCount.Load())
		fmt.Fprintf(w, "# HELP cliproxy_upstream_up Whether upstream is reachable\n")
		fmt.Fprintf(w, "# TYPE cliproxy_upstream_up gauge\n")
		fmt.Fprintf(w, "cliproxy_upstream_up %d\n", upstreamUp)
	}
}

// usageHandler returns token usage statistics
func (s *Server) usageHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		// Handle reset request
		if r.Method == http.MethodDelete || r.URL.Query().Get("reset") == "true" {
			handlers.ResetUsageStats()
			w.Write([]byte(`{"status":"reset","message":"Usage stats have been reset"}`))
			return
		}

		stats := handlers.GetUsageStats()
		json.NewEncoder(w).Encode(stats)
	}
}

// defaultHandler proxies unhandled routes
func (s *Server) defaultHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s.requestCount.Add(1)
		if s.cfg.LogRequests {
			log.Printf("[%s] %s %s", r.Method, r.URL.Path, r.RemoteAddr)
		}
		if flusher, ok := w.(http.Flusher); ok {
			s.proxy.ServeHTTP(&flushWriter{w, flusher}, r)
		} else {
			s.proxy.ServeHTTP(w, r)
		}
	}
}

// healthChecker periodically checks upstream health
func (s *Server) healthChecker() {
	client := &http.Client{Timeout: 5 * time.Second}
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	// Initial check
	s.checkUpstream(client)

	for range ticker.C {
		s.checkUpstream(client)
	}
}

func (s *Server) checkUpstream(client *http.Client) {
	url := fmt.Sprintf("%s/v1/models", s.cfg.UpstreamURL)
	req, _ := http.NewRequest("GET", url, nil)
	if s.cfg.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.cfg.APIKey)
	}

	resp, err := client.Do(req)
	if err != nil {
		if s.upstreamHealth.Load() {
			log.Printf("⚠️  Upstream became unavailable: %v", err)
		}
		s.upstreamHealth.Store(false)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		if !s.upstreamHealth.Load() {
			log.Printf("✅ Upstream is now available")
		}
		s.upstreamHealth.Store(true)
	} else {
		if s.upstreamHealth.Load() {
			log.Printf("⚠️  Upstream returned status %d", resp.StatusCode)
		}
		s.upstreamHealth.Store(false)
	}
}

// waitForShutdown handles graceful shutdown
func (s *Server) waitForShutdown() {
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit

	log.Printf("🛑 Received signal %v, initiating graceful shutdown...", sig)
	s.healthy.Store(false)

	// Give load balancers time to stop sending traffic
	time.Sleep(2 * time.Second)

	// Create shutdown context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Shutdown server
	if err := s.httpServer.Shutdown(ctx); err != nil {
		log.Printf("⚠️  Shutdown error: %v", err)
	} else {
		log.Printf("✅ Server shutdown complete")
	}

	log.Printf("📊 Final stats: %d requests served, uptime: %s",
		s.requestCount.Load(), time.Since(s.startTime).Round(time.Second))
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
