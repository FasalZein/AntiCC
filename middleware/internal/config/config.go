package config

import (
	"flag"
	"os"
)

// Config holds the middleware configuration
type Config struct {
	Port            int
	UpstreamURL     string
	APIKey          string
	Debug           bool
	LogRequests     bool
	TokenMultiplier float64
}

// Load parses flags and environment variables to build config
func Load() *Config {
	cfg := &Config{}

	flag.IntVar(&cfg.Port, "port", 8318, "Port to listen on")
	flag.StringVar(&cfg.UpstreamURL, "upstream", "http://127.0.0.1:8317", "CLIProxyAPI upstream URL")
	flag.StringVar(&cfg.APIKey, "api-key", "", "API key for authentication (optional)")
	flag.BoolVar(&cfg.Debug, "debug", false, "Enable debug logging")
	flag.BoolVar(&cfg.LogRequests, "log-requests", false, "Log all requests")
	flag.Float64Var(&cfg.TokenMultiplier, "token-multiplier", 4.0, "Character to token ratio")
	flag.Parse()

	// Environment variable overrides
	if cfg.UpstreamURL == "http://127.0.0.1:8317" {
		if envURL := os.Getenv("CLIPROXY_UPSTREAM_URL"); envURL != "" {
			cfg.UpstreamURL = envURL
		}
	}
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("CLIPROXY_API_KEY")
	}

	return cfg
}
