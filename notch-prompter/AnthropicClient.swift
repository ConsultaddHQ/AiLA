import Foundation

enum AnthropicError: Error, LocalizedError {
    case missingAPIKey
    case http(status: Int, body: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key not set in Settings."
        case .http(let status, _):
            return "Anthropic API returned HTTP \(status)."
        case .decoding:
            return "Could not decode Anthropic response."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// Streaming events emitted while generating an interview answer.
enum AnswerStreamEvent {
    case delta(String)
    case usage(cacheRead: Int, cacheWrite: Int)
    case done
}

struct AnthropicClient {
    private let session: URLSession
    private let model: String

    init(
        session: URLSession = .shared,
        model: String = "claude-sonnet-4-6"
    ) {
        self.session = session
        self.model = model
    }

    /// Streams an interview answer using the Interview Ace prompt + the user's
    /// setup context + the full conversation history. Each `delta` event is a
    /// partial text fragment; concatenate them for the full answer.
    func streamAnswer(
        history: [ConversationTurn],
        setup: InterviewSetup
    ) -> AsyncThrowingStream<AnswerStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runStream(history: history, setup: setup, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        history: [ConversationTurn],
        setup: InterviewSetup,
        continuation: AsyncThrowingStream<AnswerStreamEvent, Error>.Continuation
    ) async throws {
        guard let key = Credentials.get(.anthropic), !key.isEmpty else {
            throw AnthropicError.missingAPIKey
        }

        var systemBlocks: [RequestBody.SystemBlock] = [
            .init(text: InterviewAcePrompt.text)
        ]
        let setupBlock = setup.renderedContextBlock
        if !setupBlock.isEmpty {
            systemBlocks.append(.init(text: setupBlock))
        }

        let messages = history.map { turn -> RequestBody.Message in
            RequestBody.Message(
                role: turn.role == .interviewer ? "user" : "assistant",
                content: turn.text
            )
        }
        // Anthropic requires the conversation start with a user turn. If somehow
        // it doesn't, prepend a placeholder so the request doesn't 400.
        let safeMessages: [RequestBody.Message] = {
            if let first = messages.first, first.role == "user" { return messages }
            return [.init(role: "user", content: "(start of interview)")] + messages
        }()

        let body = RequestBody(
            model: model,
            max_tokens: 400,
            stream: true,
            system: systemBlocks,
            messages: safeMessages
        )

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch {
            throw AnthropicError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            var bodyStr = ""
            for try await line in bytes.lines {
                bodyStr += line + "\n"
                if bodyStr.count > 4000 { break }
            }
            throw AnthropicError.http(status: http.statusCode, body: bodyStr)
        }

        var cacheRead = 0
        var cacheWrite = 0

        for try await rawLine in bytes.lines {
            if Task.isCancelled { break }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }

            guard let data = payload.data(using: .utf8) else { continue }
            guard let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

            switch event.type {
            case "content_block_delta":
                if let delta = event.delta, delta.type == "text_delta", let text = delta.text {
                    continuation.yield(.delta(text))
                }
            case "message_start":
                if let usage = event.message?.usage {
                    cacheRead = usage.cache_read_input_tokens ?? 0
                    cacheWrite = usage.cache_creation_input_tokens ?? 0
                }
            case "message_delta":
                if let usage = event.usage {
                    cacheRead += usage.cache_read_input_tokens ?? 0
                    cacheWrite += usage.cache_creation_input_tokens ?? 0
                }
            case "message_stop":
                continuation.yield(.usage(cacheRead: cacheRead, cacheWrite: cacheWrite))
                continuation.yield(.done)
                continuation.finish()
                return
            default:
                continue
            }
        }
        continuation.yield(.usage(cacheRead: cacheRead, cacheWrite: cacheWrite))
        continuation.yield(.done)
        continuation.finish()
    }
}

// MARK: - Request shapes

private struct RequestBody: Encodable {
    let model: String
    let max_tokens: Int
    let stream: Bool
    let system: [SystemBlock]
    let messages: [Message]

    struct SystemBlock: Encodable {
        let type = "text"
        let text: String
        let cache_control = CacheControl(type: "ephemeral")
    }

    struct CacheControl: Encodable {
        let type: String
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

// MARK: - Streaming event shapes

private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let message: MessageInfo?
    let usage: Usage?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct MessageInfo: Decodable {
        let usage: Usage?
    }

    struct Usage: Decodable {
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let input_tokens: Int?
        let output_tokens: Int?
    }
}

