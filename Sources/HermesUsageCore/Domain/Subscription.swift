import Foundation

public enum Subscription: String, CaseIterable, Codable, Hashable, Sendable {
    case nousPortal = "nous-portal"
    case opencodeGo = "opencode-go"
    case chatGPT = "chatgpt"
}
