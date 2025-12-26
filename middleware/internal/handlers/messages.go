package handlers

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"strings"

	"cliproxy-middleware/internal/config"
	"cliproxy-middleware/internal/schema"
)

// Messages intercepts /v1/messages to normalize tool schemas and map model names
func Messages(cfg *config.Config, proxy *httputil.ReverseProxy) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cfg.Debug {
			log.Printf("[messages] received %s %s", r.Method, r.URL.Path)
		}

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

		// Parse request
		var rawRequest map[string]json.RawMessage
		if err := json.Unmarshal(body, &rawRequest); err != nil {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		modified := false

		// Map model name to Antigravity equivalent
		if modelRaw, hasModel := rawRequest["model"]; hasModel {
			var model string
			if err := json.Unmarshal(modelRaw, &model); err == nil {
				mappedModel := config.MapModel(model)
				if mappedModel != model {
					if cfg.Debug {
						log.Printf("[messages] model mapped: %s -> %s", model, mappedModel)
					}
					newModelJSON, _ := json.Marshal(mappedModel)
					rawRequest["model"] = newModelJSON
					modified = true
				}
			}
		}

		// Check if there are tools to normalize
		toolsRaw, hasTools := rawRequest["tools"]
		if cfg.Debug {
			keys := make([]string, 0, len(rawRequest))
			for k := range rawRequest {
				keys = append(keys, k)
			}
			log.Printf("[messages] request keys: %v, hasTools: %v", keys, hasTools)
			if hasTools {
				log.Printf("[messages] tools length: %d bytes", len(toolsRaw))
			}
		}

		// Normalize tools if present
		if hasTools && len(toolsRaw) > 0 && string(toolsRaw) != "null" {
			var tools []map[string]interface{}
			if err := json.Unmarshal(toolsRaw, &tools); err == nil {
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
				}
			}
		}

		// Apply modifications if any
		if modified {
			newBody, _ := json.Marshal(rawRequest)
			if cfg.Debug {
				log.Printf("[messages] request modified, %d -> %d bytes", len(body), len(newBody))
			}
			r.Body = io.NopCloser(bytes.NewReader(newBody))
			r.ContentLength = int64(len(newBody))
		} else {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
		}

		serveProxyWithUsage(w, r, proxy, cfg.Debug)
	}
}

func serveProxy(w http.ResponseWriter, r *http.Request, proxy *httputil.ReverseProxy) {
	serveProxyWithUsage(w, r, proxy, false)
}

func serveProxyWithUsage(w http.ResponseWriter, r *http.Request, proxy *httputil.ReverseProxy, debug bool) {
	// Wrap writer to capture usage from responses
	uw := &usageTrackingWriter{
		ResponseWriter: w,
		debug:          debug,
	}
	if flusher, ok := w.(http.Flusher); ok {
		uw.flusher = flusher
	}
	proxy.ServeHTTP(uw, r)
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

// usageTrackingWriter wraps ResponseWriter to extract usage from API responses
type usageTrackingWriter struct {
	http.ResponseWriter
	flusher     http.Flusher
	debug       bool
	isStreaming bool
	headersSent bool
}

func (uw *usageTrackingWriter) WriteHeader(statusCode int) {
	uw.headersSent = true
	contentType := uw.Header().Get("Content-Type")
	uw.isStreaming = strings.Contains(contentType, "text/event-stream")
	uw.ResponseWriter.WriteHeader(statusCode)
}

func (uw *usageTrackingWriter) Write(p []byte) (int, error) {
	// Track usage from response data
	if uw.isStreaming {
		// Parse SSE events for usage data
		uw.parseStreamingUsage(p)
	} else {
		// For non-streaming, check if this looks like a complete response
		TrackUsageFromResponse(p, false, uw.debug)
	}

	n, err := uw.ResponseWriter.Write(p)
	if uw.flusher != nil {
		uw.flusher.Flush()
	}
	return n, err
}

// parseStreamingUsage extracts usage from SSE events
func (uw *usageTrackingWriter) parseStreamingUsage(data []byte) {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "data: ") {
			jsonData := strings.TrimPrefix(line, "data: ")
			if jsonData == "[DONE]" {
				continue
			}
			// Look for message_delta with usage info
			var event struct {
				Type  string         `json:"type"`
				Usage *AnthropicUsage `json:"usage,omitempty"`
			}
			if err := json.Unmarshal([]byte(jsonData), &event); err == nil {
				if event.Usage != nil {
					addUsage(event.Usage, uw.debug)
				}
			}
		}
	}
}

func (uw *usageTrackingWriter) Flush() {
	if uw.flusher != nil {
		uw.flusher.Flush()
	}
}
