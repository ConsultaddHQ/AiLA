import Foundation

enum STTError: Error, LocalizedError {
    case missingAPIKey
    case http(status: Int, body: String)
    case decoding(Error)
    case transport(Error)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ElevenLabs API key not set in Settings."
        case .http(let status, _):
            return "ElevenLabs API returned HTTP \(status)."
        case .decoding:
            return "Could not decode ElevenLabs response."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .empty:
            return "No speech detected."
        }
    }
}

struct ElevenLabsSTT {
    private let session: URLSession
    private let modelID: String

    init(session: URLSession = .shared, modelID: String = "scribe_v1") {
        self.session = session
        self.modelID = modelID
    }

    func transcribe(wavURL: URL) async throws -> String {
        guard let key = Credentials.get(.elevenLabs), !key.isEmpty else {
            throw STTError.missingAPIKey
        }

        let boundary = "----notchprompter-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 60
        req.httpBody = try makeMultipartBody(boundary: boundary, wavURL: wavURL)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw STTError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw STTError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw STTError.http(status: http.statusCode, body: bodyStr)
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw STTError.empty }
            return text
        } catch let error as STTError {
            throw error
        } catch {
            throw STTError.decoding(error)
        }
    }

    private func makeMultipartBody(boundary: String, wavURL: URL) throws -> Data {
        var body = Data()
        let prefix = "--\(boundary)\r\n"
        let audioData = try Data(contentsOf: wavURL)
        let filename = wavURL.lastPathComponent

        body.appendString(prefix)
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")

        body.appendString(prefix)
        body.appendString("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        body.appendString(modelID)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private struct ResponseBody: Decodable {
    let text: String
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
