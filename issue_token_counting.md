# Token counting endpoint `/v1/messages/count_tokens` significantly undercounts tokens

**Describe the bug**
The `/v1/messages/count_tokens` endpoint returns significantly fewer tokens than the actual token count used when making a real `/v1/messages` request. The endpoint appears to only count message content tokens while ignoring:
- System prompts
- Tool definitions
- Message formatting overhead

The `count_tokens` endpoint returns **48 tokens** but the actual request uses **728 tokens** - a difference of **680 tokens** (93% undercount).

**CLI Type**
claude code (via antigravity)

**Model Name**
- gemini-claude-sonnet-4-5-thinking
- gemini-claude-opus-4-5-thinking
- (Likely affects all models)

**LLM Client**
- Claude Code (via anticc)
- Roo Code v3.36.x
- Any client using `/v1/messages/count_tokens` for token estimation

**Request Information**

### Test 1: Token Count Request

```bash
curl -v http://127.0.0.1:8317/v1/messages/count_tokens \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "gemini-claude-sonnet-4-5-thinking",
    "system": "You are Claude, a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices.",
    "messages": [
      {"role": "user", "content": "Can you help me refactor this code?"},
      {"role": "assistant", "content": "Of course! Please share the code you would like me to refactor."},
      {"role": "user", "content": "Here is my Python function:\n\ndef calc(x,y,z):\n  return x+y*z"}
    ],
    "tools": [
      {"name": "read_file", "description": "Read a file from disk", "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
      {"name": "write_file", "description": "Write content to a file", "input_schema": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}},
      {"name": "execute_command", "description": "Run a shell command", "input_schema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}
    ]
  }'
```

**Verbose curl output:**
```
*   Trying 127.0.0.1:8317...
* Connected to 127.0.0.1 (127.0.0.1) port 8317
> POST /v1/messages/count_tokens HTTP/1.1
> Host: 127.0.0.1:8317
> User-Agent: curl/8.7.1
> Accept: */*
> Content-Type: application/json
> x-api-key: sk-****
> anthropic-version: 2023-06-01
> Content-Length: 1123
> 
< HTTP/1.1 200 OK
< Access-Control-Allow-Headers: *
< Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
< Access-Control-Allow-Origin: *
< Content-Type: application/json
< Date: Mon, 22 Dec 2025 20:38:35 GMT
< Content-Length: 19
```

**Response:**
```json
{"input_tokens":48}
```

---

### Test 2: Actual Message Request (SAME PAYLOAD)

```bash
curl -v http://127.0.0.1:8317/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "gemini-claude-sonnet-4-5-thinking",
    "max_tokens": 50,
    "system": "You are Claude, a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices.",
    "messages": [
      {"role": "user", "content": "Can you help me refactor this code?"},
      {"role": "assistant", "content": "Of course! Please share the code you would like me to refactor."},
      {"role": "user", "content": "Here is my Python function:\n\ndef calc(x,y,z):\n  return x+y*z"}
    ],
    "tools": [
      {"name": "read_file", "description": "Read a file from disk", "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
      {"name": "write_file", "description": "Write content to a file", "input_schema": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}},
      {"name": "execute_command", "description": "Run a shell command", "input_schema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}
    ]
  }'
```

**Verbose curl output:**
```
*   Trying 127.0.0.1:8317...
* Connected to 127.0.0.1 (127.0.0.1) port 8317
> POST /v1/messages HTTP/1.1
> Host: 127.0.0.1:8317
> User-Agent: curl/8.7.1
> Accept: */*
> Content-Type: application/json
> x-api-key: sk-****
> anthropic-version: 2023-06-01
> Content-Length: 1145
> 
< HTTP/1.1 200 OK
< Access-Control-Allow-Headers: *
< Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
< Access-Control-Allow-Origin: *
< Content-Type: application/json
< Date: Mon, 22 Dec 2025 20:38:38 GMT
< Content-Length: 433
```

**Response:**
```json
{
  "id": "req_vrtx_011CWNNRBUNqzQf9nULgjWuS",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-4-5-thinking",
  "content": [
    {
      "type": "text",
      "text": "I'd be happy to help you refactor this code! Here's an improved version with better practices:\n\n```python\ndef calculate_sum_with_product(x: float, y: float, z: float) -> float:"
    }
  ],
  "stop_reason": "max_tokens",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 728,
    "output_tokens": 50
  }
}
```

---

### CLIProxyAPI Server Logs (with `debug: true` and `request-log: true`)

```
[2025-12-23 02:08:04] [info] [main.go:413] CLIProxyAPI Version: 6.6.42, Commit: Homebrew, BuiltAt: 2025-12-22T14:52:23Z
[2025-12-23 02:08:04] [info] [util.go:30] log level changed from info to debug (debug=true)
[2025-12-23 02:08:04] [info] [global_logger.go:67] [WARNING] Running in "debug" mode. Switch to "release" mode in production.
[2025-12-23 02:08:04] [info] [global_logger.go:67] POST   /v1/messages/count_tokens --> github.com/router-for-me/CLIProxyAPI/v6/sdk/api/handlers/claude.(*ClaudeCodeAPIHandler).ClaudeCountTokens-fm (6 handlers)
[2025-12-23 02:08:04] [info] [global_logger.go:67] POST   /v1/messages              --> github.com/router-for-me/CLIProxyAPI/v6/sdk/api/handlers/claude.(*ClaudeCodeAPIHandler).ClaudeMessages-fm (6 handlers)
...
[2025-12-23 02:08:35] [debug] [manager.go:462] Use OAuth [REDACTED]@gmail.com for model gemini-claude-sonnet-4-5-thinking
[2025-12-23 02:08:35] [info] [gin_logger.go:64] [GIN] 2025/12/23 - 02:08:35 | 200 |         581ms |       127.0.0.1 | POST    "/v1/messages/count_tokens"
[2025-12-23 02:08:35] [debug] [manager.go:402] Use OAuth [REDACTED]@gmail.com for model gemini-claude-sonnet-4-5-thinking
[2025-12-23 02:08:38] [info] [gin_logger.go:64] [GIN] 2025/12/23 - 02:08:38 | 200 |        2.823s |       127.0.0.1 | POST    "/v1/messages"
```

**Expected behavior**
The `/v1/messages/count_tokens` endpoint should return a token count that matches (or closely approximates) the `input_tokens` value returned in the `usage` object of an actual `/v1/messages` response.

For the test payload above:
- **Expected**: `{"input_tokens": 728}` (matching actual usage)
- **Actual**: `{"input_tokens": 48}` (93% undercount)

**Screenshots**
N/A

**OS Type**
- OS: macOS
- Version: 15.2

**Additional context**

CLIProxyAPI Version:
```
CLIProxyAPI Version: 6.6.42, Commit: Homebrew, BuiltAt: 2025-12-22T14:52:23Z
```

**Token comparison (same payload for both requests):**

| Metric | count_tokens | /v1/messages | Difference |
|--------|-------------|--------------|------------|
| **input_tokens** | 48 | 728 | **680 tokens (93% undercount)** |
| Request payload size | 1123 bytes | 1145 bytes | 22 bytes (max_tokens field) |

**Payload breakdown (estimated):**

| Component | Estimated Tokens | Notes |
|-----------|-----------------|-------|
| System prompt | ~40 | 159 chars |
| Messages (3 total) | ~48 | 193 chars |
| Tools (3 definitions) | ~200 | 800 chars with schemas |
| Role/formatting overhead | ~40 | ~10-15 per message |
| **Total Expected** | **~328** | |
| **count_tokens returned** | **48** | Only counts message content |
| **Actual usage** | **728** | Ground truth from API |

**Impact:**
- **Inaccurate cost estimates** - Users think they're using fewer tokens than they actually are
- **Context window miscalculation** - Clients may not properly truncate/summarize when approaching limits
- **Billing surprises** - Actual usage is ~15x higher than estimated

**Root cause analysis:**

The handler at `github.com/router-for-me/CLIProxyAPI/v6/sdk/api/handlers/claude.(*ClaudeCodeAPIHandler).ClaudeCountTokens-fm` appears to only count message content tokens (48 tokens ≈ the message text only).

**Suggested fix:**
The token counting logic in `ClaudeCountTokens` should include:
1. System prompt tokens (`system` field)
2. Tool definition tokens (`tools` array including `name`, `description`, and `input_schema`)
3. Message content tokens (`messages` array)
4. Role/formatting overhead tokens (~3-4 tokens per message for role markers)