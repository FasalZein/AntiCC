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

// ChatCompletions intercepts /v1/chat/completions to normalize tool schemas for Gemini compatibility
// OpenAI format uses tools[].function.parameters instead of tools[].input_schema
func ChatCompletions(cfg *config.Config, proxy *httputil.ReverseProxy) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if cfg.Debug {
			log.Printf("[chat] received %s %s", r.Method, r.URL.Path)
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
		if cfg.Debug {
			keys := make([]string, 0, len(rawRequest))
			for k := range rawRequest {
				keys = append(keys, k)
			}
			log.Printf("[chat] request keys: %v, hasTools: %v", keys, hasTools)
			if hasTools {
				log.Printf("[chat] tools length: %d bytes", len(toolsRaw))
			}
		}
		if !hasTools || len(toolsRaw) == 0 || string(toolsRaw) == "null" {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		// Parse and normalize tools (OpenAI format)
		var tools []map[string]interface{}
		if err := json.Unmarshal(toolsRaw, &tools); err != nil {
			r.Body = io.NopCloser(bytes.NewReader(body))
			r.ContentLength = int64(len(body))
			serveProxy(w, r, proxy)
			return
		}

		modified := false
		for i, tool := range tools {
			// OpenAI format: tools[].function.parameters
			if function, exists := tool["function"]; exists {
				if funcMap, ok := function.(map[string]interface{}); ok {
					if parameters, hasParams := funcMap["parameters"]; hasParams {
						if schemaMap, ok := parameters.(map[string]interface{}); ok {
							originalJSON, _ := json.Marshal(schemaMap)
							normalized := schema.Normalize(schemaMap, cfg.Debug)
							normalizedJSON, _ := json.Marshal(normalized)

							if string(originalJSON) != string(normalizedJSON) {
								modified = true
								funcMap["parameters"] = normalized
								tools[i]["function"] = funcMap
								if cfg.Debug {
									if name, ok := funcMap["name"].(string); ok {
										log.Printf("[chat] normalized tool: %s", name)
									}
								}
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
				log.Printf("[chat] schema normalized, %d -> %d bytes", len(body), len(newBody))
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