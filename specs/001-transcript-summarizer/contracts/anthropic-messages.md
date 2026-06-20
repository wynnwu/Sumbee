# Contract: Anthropic Messages (outbound)

`AnthropicClient` is the only component that talks to the summarization service. It is
used exclusively from off the main actor and never sees the UI.

## Surface

```swift
struct SummarizationRequest {
    var model: String
    var systemPrompt: String          // style prompt + format-aware output convention
    var userText: String              // transcript (+ light video metadata)
    var maxTokens: Int
    var temperature: Double?          // nil unless model.supportsTemperature
    var effort: String?               // nil unless model.supportsEffort
    var extendedThinking: Bool        // adaptive thinking, only where supported
}

protocol AnthropicStreaming {
    /// Streams text deltas; returns the full assembled text on completion.
    func stream(_ req: SummarizationRequest,
                apiKey: String,
                onDelta: @escaping (String) -> Void) async throws -> String
    /// Cheap validation call for "Save & Validate".
    func validateKey(_ apiKey: String, model: String) async -> Result<Void, AnthropicError>
}
```

## Wire request

- `POST https://api.anthropic.com/v1/messages`
- Headers: `x-api-key: <key>`, `anthropic-version: 2023-06-01`,
  `content-type: application/json`
- Body (capability-gated):

```json
{
  "model": "claude-opus-4-8",
  "max_tokens": 4096,
  "stream": true,
  "system": "<style prompt + output convention (+ HTML styling prompt if HTML)>",
  "messages": [{ "role": "user", "content": "<transcript>" }]
}
```

- `temperature` is added **only** when `capabilities.supportsTemperature`.
- `output_config.effort` is added **only** when `capabilities.supportsEffort` and the
  user selected a level.
- `thinking: {"type":"adaptive"}` is added **only** when extended thinking is on and
  supported; default summarization leaves it off (faithful mode).
- No `temperature`/`budget_tokens` is ever sent to Opus 4.8/4.7 (they 400).

## Streaming (SSE)

Parse `text/event-stream` lines; accumulate `content_block_delta` → `delta.text_delta`
into the output and forward each delta via `onDelta`. Stop on `message_stop`. Cancellation
is via Swift task cancellation, which tears down the URLSession byte stream.

## Error mapping → `AnthropicError`

| HTTP / condition | `AnthropicError` | App behavior |
|---|---|---|
| 401 | `.invalidKey` | Re-gate to Settings; "fix your key". |
| 429 | `.rateLimited(retryAfter)` | Backoff + retry with a notice. |
| 529 / 5xx | `.overloaded` | Backoff + retry with a notice. |
| timeout / offline | `.network` | Offer retry; never silently fail. |
| 400 + other | `.badRequest(message)` | Surface friendly message. |

The key is passed in only as a function argument, never stored on the client, never
logged. On `.invalidKey`, `AppState` flips the key-gate and routes to Settings.
