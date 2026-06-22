import Foundation

/// A summarization request, already capability-resolved by the caller: `temperature`,
/// `effort`, and `extendedThinking` are set only when the chosen model accepts them.
public struct SummarizationRequest: Sendable {
    public var model: String
    public var systemPrompt: String
    public var userText: String
    public var maxTokens: Int
    public var temperature: Double?
    public var effort: String?
    public var extendedThinking: Bool

    public init(model: String, systemPrompt: String, userText: String, maxTokens: Int,
                temperature: Double? = nil, effort: String? = nil, extendedThinking: Bool = false) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userText = userText
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.effort = effort
        self.extendedThinking = extendedThinking
    }
}

public enum AnthropicError: Error, Equatable, Sendable {
    case invalidKey
    case rateLimited(retryAfter: Int?)
    case overloaded
    /// 403/404 - model not available, no access, or region/VPN-blocked. Retryable: the user
    /// can fix their environment (e.g. VPN country) and the queue will succeed.
    case unavailable(String)
    case network(String)
    case badRequest(String)
    case emptyResponse

    public var isAuth: Bool { self == .invalidKey }

    /// True for transient/environmental failures worth retrying with backoff (FR-021).
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .unavailable, .network: return true
        case .invalidKey, .badRequest, .emptyResponse: return false
        }
    }

    public var userMessage: String {
        switch self {
        case .invalidKey: return "The API key was rejected (401). Check it in Settings."
        case .rateLimited(let s): return "Rate limited\(s.map { " (retry in \($0)s)" } ?? ""). Please try again shortly."
        case .overloaded: return "The service is busy right now. Please try again shortly."
        case .unavailable(let m): return "Model unavailable: \(m) Check the model id, your access, or that your VPN routes to a permitted country."
        case .network(let m): return "Network problem: \(m)"
        case .badRequest(let m): return "Request rejected: \(m)"
        case .emptyResponse: return "The model returned no content."
        }
    }
}

/// A model id + display name as returned by `GET /v1/models`.
public struct RemoteModel: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public protocol AnthropicStreaming: Sendable {
    /// Stream a summary. `onDelta` is called with incremental text; the full text is returned.
    func stream(_ request: SummarizationRequest,
                apiKey: String,
                onDelta: @escaping @Sendable (String) -> Void) async throws -> String

    /// A cheap call used by Settings' "Save & Validate".
    func validateKey(_ apiKey: String, model: String) async -> Result<Void, AnthropicError>

    /// The models available to this account (`GET /v1/models`). Returns [] on any failure.
    func listModels(_ apiKey: String) async -> [RemoteModel]
}

/// Anthropic Messages API client over `URLSession` with manual SSE parsing, no SDK.
public struct AnthropicClient: AnthropicStreaming {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2023-06-01"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func makeRequest(_ req: SummarizationRequest, apiKey: String, stream: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": req.model,
            "max_tokens": req.maxTokens,
            "system": req.systemPrompt,
            "messages": [["role": "user", "content": req.userText]],
        ]
        if stream { body["stream"] = true }
        if let t = req.temperature { body["temperature"] = t }
        if let e = req.effort { body["output_config"] = ["effort": e] }
        if req.extendedThinking { body["thinking"] = ["type": "adaptive"] }

        var urlReq = URLRequest(url: Self.endpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlReq.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlReq.setValue("application/json", forHTTPHeaderField: "content-type")
        urlReq.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return urlReq
    }

    public func stream(_ request: SummarizationRequest,
                       apiKey: String,
                       onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let urlReq = try makeRequest(request, apiKey: apiKey, stream: true)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: urlReq)
        } catch {
            // URLSession surfaces task cancellation as URLError(.cancelled); preserve it as
            // a CancellationError so a user-cancelled job isn't mistaken for a retryable network error.
            if (error as? CancellationError) != nil || Task.isCancelled { throw CancellationError() }
            throw AnthropicError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.network("No HTTP response")
        }

        if http.statusCode != 200 {
            // Drain the (small) error body for a useful message.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.mapError(status: http.statusCode, body: data, headers: http)
        }

        var assembled = ""
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty || payload == "[DONE]" { continue }
                guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                switch type {
                case "content_block_delta":
                    if let delta = json["delta"] as? [String: Any],
                       (delta["type"] as? String) == "text_delta",
                       let text = delta["text"] as? String {
                        assembled += text
                        onDelta(text)
                    }
                case "message_stop":
                    break
                case "error":
                    if let err = json["error"] as? [String: Any],
                       let msg = err["message"] as? String {
                        throw AnthropicError.badRequest(msg)
                    }
                default:
                    break
                }
            }
        } catch let e as AnthropicError {
            throw e
        } catch {
            if (error as? CancellationError) != nil || Task.isCancelled { throw CancellationError() }
            throw AnthropicError.network(error.localizedDescription)
        }

        if assembled.isEmpty { throw AnthropicError.emptyResponse }
        return assembled
    }

    public func validateKey(_ apiKey: String, model: String) async -> Result<Void, AnthropicError> {
        let req = SummarizationRequest(model: model,
                                       systemPrompt: "You are a connectivity check.",
                                       userText: "Reply with: ok",
                                       maxTokens: 16)
        do {
            let urlReq = try makeRequest(req, apiKey: apiKey, stream: false)
            let (data, response) = try await session.data(for: urlReq)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("No HTTP response"))
            }
            if http.statusCode == 200 { return .success(()) }
            return .failure(Self.mapError(status: http.statusCode, body: data, headers: http))
        } catch let e as AnthropicError {
            return .failure(e)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    public func listModels(_ apiKey: String) async -> [RemoteModel] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else { return [] }
            return arr.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                let name = (item["display_name"] as? String) ?? id
                return RemoteModel(id: id, displayName: name)
            }
        } catch {
            return []
        }
    }

    // MARK: - Error mapping

    static func mapError(status: Int, body: Data, headers: HTTPURLResponse) -> AnthropicError {
        let message = extractMessage(body) ?? "HTTP \(status)"
        switch status {
        case 401: return .invalidKey
        case 403, 404: return .unavailable(message)
        case 429:
            let retry = headers.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
            return .rateLimited(retryAfter: retry)
        case 529: return .overloaded
        case 500...599: return .overloaded
        default: return .badRequest(message)
        }
    }

    static func extractMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["error"] as? [String: Any],
              let msg = err["message"] as? String else { return nil }
        return msg
    }
}
