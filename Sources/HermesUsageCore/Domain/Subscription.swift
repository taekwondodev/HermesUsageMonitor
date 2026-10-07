import Foundation

public enum Subscription: String, CaseIterable, Codable, Sendable {
    case chatGPT = "chatgpt"
    case claude = "claude"
}
