package proxy

import (
	"bytes"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"cliproxy-middleware/internal/config"
)

// New creates a configured reverse proxy to the upstream CLIProxyAPI
func New(cfg *config.Config) (*httputil.ReverseProxy, error) {
	upstream, err := url.Parse(cfg.UpstreamURL)
	if err != nil {
		return nil, err
	}

	proxy := httputil.NewSingleHostReverseProxy(upstream)

	if cfg.Debug {
		proxy.Transport = &loggingTransport{http.DefaultTransport}
	}

	// Modify director for streaming
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Header.Del("Accept-Encoding")
	}

	// Handle streaming responses
	proxy.ModifyResponse = func(resp *http.Response) error {
		if strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream") {
			resp.Header.Del("Content-Length")
		}
		return nil
	}

	return proxy, nil
}

type loggingTransport struct {
	transport http.RoundTripper
}

func (t *loggingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	log.Printf("[DEBUG] → %s %s", req.Method, req.URL.String())

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
