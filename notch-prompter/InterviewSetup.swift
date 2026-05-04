import Foundation

/// Per-interview lightweight context the user fills in from the setup wizard.
/// Following the Interview Ace prompt: small, focused, no resume dump.
/// The interviewer's company drives domain-mirrored language in every answer,
/// which is why it's the only field we treat as required.
struct InterviewSetup: Codable, Equatable {
    var interviewerName: String = ""
    var interviewerCompany: String = ""
    var currentEmployer: String = ""
    var currentProject: String = ""
    /// Free-form multi-line. One past company per line, e.g.
    /// "AcmeCo — built the ML pipeline"
    /// "FoobarCorp — led platform team"
    var pastCompanies: String = ""

    static let empty = InterviewSetup()

    /// Minimum context the LLM needs to mirror the interviewer's domain.
    var isComplete: Bool {
        !interviewerCompany.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !currentEmployer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Rendered context block, ready to embed as a cached system message
    /// after the Interview Ace operating principles.
    var renderedContextBlock: String {
        var lines: [String] = ["Interview context:"]

        let interviewerLabel: String = {
            let n = interviewerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = interviewerCompany.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (n.isEmpty, c.isEmpty) {
            case (false, false): return "\(n) at \(c)"
            case (true,  false): return c
            case (false, true):  return n
            case (true,  true):  return ""
            }
        }()
        if !interviewerLabel.isEmpty {
            lines.append("- Interviewer: \(interviewerLabel)")
        }

        let employer = currentEmployer.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = currentProject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !employer.isEmpty {
            let suffix = project.isEmpty ? "" : " — \(project)"
            lines.append("- Currently: \(employer)\(suffix)")
        }

        let cleanedPast = pastCompanies
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !cleanedPast.isEmpty {
            lines.append("- Previously:")
            for company in cleanedPast.prefix(3) {
                lines.append("  • \(company)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
