import Foundation

public enum Subscription: String, CaseIterable, Codable, Sendable {
    case nousPortal = "nous-portal"
    case opencodeGo = "opencode-go"
    case chatGPT = "chatgpt"
}
