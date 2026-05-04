import Foundation

/// One turn in the interview conversation.
/// `interviewer` turns come from voice-to-text on system audio.
/// `candidate` turns are the LLM's generated answers from the previous turn —
/// we treat the model's output as "what the user spoke aloud" for context purposes.
/// (When mic capture lands later, candidate turns will switch to actual mic transcripts.)
enum TurnRole: String, Codable {
    case interviewer
    case candidate
}

struct ConversationTurn: Codable, Equatable, Identifiable {
    let id: UUID
    let role: TurnRole
    let text: String
    let timestamp: Date

    init(role: TurnRole, text: String, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Mutable conversation log for an in-progress interview.
/// Reset between interviews via `reset()`.
final class ConversationHistory: ObservableObject {
    @Published private(set) var turns: [ConversationTurn] = []

    func append(_ turn: ConversationTurn) {
        turns.append(turn)
    }

    func appendInterviewer(_ text: String) {
        turns.append(ConversationTurn(role: .interviewer, text: text))
    }

    func appendCandidate(_ text: String) {
        turns.append(ConversationTurn(role: .candidate, text: text))
    }

    func reset() {
        turns.removeAll()
    }

    /// The most recent interviewer turn — useful for the HUD's "question" caption.
    var lastInterviewerText: String? {
        turns.last(where: { $0.role == .interviewer })?.text
    }

    /// Snapshot for sending to the LLM — caller mutates the snapshot, not the live array.
    func snapshot() -> [ConversationTurn] {
        turns
    }
}
