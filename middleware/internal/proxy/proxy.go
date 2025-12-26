package proxy

import (
	"bytes"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"cliproxy-middleware/internal/config"
)

// New creates a basic reverse proxy (backwards compatibility)
func New(cfg *config.Config) (*httputil.ReverseProxy, error) {
	return NewWithPool(cfg)
}

// NewWithPool creates a reverse proxy with connection pooling for better performance
func NewWithPool(cfg *config.Config) (*httputil.ReverseProxy, error) {
	upstream, err := url.Parse(cfg.UpstreamURL)
	if err != nil {
		return nil, err
	}

	// Create optimized transport with connection pooling
	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          100,
		MaxIdleConnsPerHost:   20,
		MaxConnsPerHost:       100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ResponseHeaderTimeout: 5 * time.Minute, // Long for LLM responses
		DisableCompression:    true,            // We handle our own compression
	}

	proxy := httputil.NewSingleHostReverseProxy(upstream)

	// Use pooled transport
	if cfg.Debug {
		proxy.Transport = &loggingTransport{transport}
	} else {
		proxy.Transport = transport
	}

	// Modify director for streaming
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		// Remove Accept-Encoding to get uncompressed responses for streaming
		req.Header.Del("Accept-Encoding")
		// Set connection to keep-alive
		req.Header.Set("Connection", "keep-alive")
	}

	// Handle streaming responses
	proxy.ModifyResponse = func(resp *http.Response) error {
		contentType := resp.Header.Get("Content-Type")
		if strings.Contains(contentType, "text/event-stream") ||
			strings.Contains(contentType, "application/x-ndjson") {
			// Remove Content-Length for streaming
			resp.Header.Del("Content-Length")
			// Disable buffering
			resp.Header.Set("X-Accel-Buffering", "no")
			resp.Header.Set("Cache-Control", "no-cache")
		}
		return nil
	}

	// Handle proxy errors gracefully
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("⚠️  Proxy error: %v (path: %s)", err, r.URL.Path)

		// Determine appropriate error response
		statusCode := http.StatusBadGateway
		errorType := "upstream_error"
		message := "Failed to connect to upstream server"

		if strings.Contains(err.Error(), "timeout") {
			statusCode = http.StatusGatewayTimeout
			message = "Upstream server timed out"
		} else if strings.Contains(err.Error(), "connection refused") {
			message = "Upstream server is not available"
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(statusCode)
		w.Write([]byte(`{"error":{"message":"` + message + `","type":"` + errorType + `"}}`))
	}

	return proxy, nil
}

type loggingTransport struct {
	transport http.RoundTripper
}

func (t *loggingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	start := time.Now()
	log.Printf("[DEBUG] → %s %s", req.Method, req.URL.String())

	if req.Body != nil && req.ContentLength > 0 && req.ContentLength < 10000 {
		body, _ := io.ReadAll(req.Body)
		req.Body = io.NopCloser(bytes.NewReader(body))
		log.Printf("[DEBUG] Request body: %s", truncate(string(body), 500))
	}

	resp, err := t.transport.RoundTrip(req)
	duration := time.Since(start)

	if err != nil {
		log.Printf("[DEBUG] ← Error after %s: %v", duration.Round(time.Millisecond), err)
		return resp, err
	}

	log.Printf("[DEBUG] ← %d %s (%s)", resp.StatusCode, resp.Status, duration.Round(time.Millisecond))
	return resp, err
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
