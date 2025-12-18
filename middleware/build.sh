#!/bin/bash
# Build the CLIProxyAPI middleware
# Requires: Go 1.21+

set -e

cd "$(dirname "$0")"

echo "Building cliproxy-middleware..."
go build -o cliproxy-middleware .

echo "Done! Binary: $(pwd)/cliproxy-middleware"
