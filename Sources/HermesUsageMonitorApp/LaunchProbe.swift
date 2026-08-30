import Darwin
import Foundation

@MainActor
enum LaunchProbe {
    private static var hasRecordedFirstAppearance = false

    static func recordFirstAppearance() {
        guard !hasRecordedFirstAppearance,
              let rawPath = getenv("HERMES_LAUNCH_PROBE_FILE"),
              let path = String(validatingCString: rawPath),
              !path.isEmpty else {
            return
        }

        hasRecordedFirstAppearance = true
        let systemUptime = ProcessInfo.processInfo.systemUptime
        let processID = ProcessInfo.processInfo.processIdentifier
        let payload = Payload(
            pid: processID,
            systemUptime: systemUptime
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let destination = URL(fileURLWithPath: path)
        Task {
            await LaunchProbeWriter.write(data, to: destination)
        }
    }
}

private enum LaunchProbeWriter {
    @concurrent
    static func write(_ data: Data, to destination: URL) async {
        try? data.write(to: destination, options: .atomic)
    }
}

private extension LaunchProbe {
    struct Payload: Encodable {
        let pid: Int32
        let systemUptime: TimeInterval
    }
}
