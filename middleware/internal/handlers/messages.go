package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httputil"

	"cliproxy-middleware/internal/config"
	"cliproxy-middleware/internal/schema"
)

// Messages intercepts /v1/messages to normalize tool schemas for Gemini compatibility
func Messages(cfg *config.Config, proxy *httputil.ReverseProxy) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			serveProxy(w, r, proxy)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, `{"error":{"message":"Failed to read request body","type":"invalid_request_error"}}`, http.StatusBadRequest)
			return
		}
		r.Body.Close()

		// Parse request to check for tools
		var rawRequest map[string]json.RawMessage
		if err := json.Unmarshal(body, &rawRequest); err != nil {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		// Check if there are tools to normalize
		toolsRaw, hasTools := rawRequest["tools"]
		if !hasTools || len(toolsRaw) == 0 || string(toolsRaw) == "null" {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		// Parse and normalize tools
		var tools []map[string]interface{}
		if err := json.Unmarshal(toolsRaw, &tools); err != nil {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		modified := false
		for i, tool := range tools {
			if inputSchema, exists := tool["input_schema"]; exists {
				if schemaMap, ok := inputSchema.(map[string]interface{}); ok {
					originalJSON, _ := json.Marshal(schemaMap)
					normalized := schema.Normalize(schemaMap, cfg.Debug)
					normalizedJSON, _ := json.Marshal(normalized)

					if string(originalJSON) != string(normalizedJSON) {
						modified = true
						tools[i]["input_schema"] = normalized
						if cfg.Debug {
							if name, ok := tool["name"].(string); ok {
								log.Printf("[messages] normalized tool: %s", name)
							}
						}
					}
				}
			}
		}

		if modified {
			normalizedTools, _ := json.Marshal(tools)
			rawRequest["tools"] = normalizedTools
			newBody, _ := json.Marshal(rawRequest)
			if cfg.Debug {
				log.Printf("[messages] schema normalized, %d -> %d bytes", len(body), len(newBody))
			}
			r.Body = io.NopCloser(bytes.NewReader(newBody))
			r.ContentLength = int64(len(newBody))
		} else {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
		}

		serveProxy(w, r, proxy)
	}
}

func serveProxy(w http.ResponseWriter, r *http.Request, proxy *httputil.ReverseProxy) {
	if flusher, ok := w.(http.Flusher); ok {
		proxy.ServeHTTP(&flushWriter{w, flusher}, r)
	} else {
		proxy.ServeHTTP(w, r)
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
