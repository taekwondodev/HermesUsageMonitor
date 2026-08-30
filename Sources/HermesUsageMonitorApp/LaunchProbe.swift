import Foundation

@MainActor
enum LaunchProbe {
    private static var hasRecordedFirstAppearance = false

    static func recordFirstAppearance(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        guard !hasRecordedFirstAppearance,
              let path = environment["HERMES_LAUNCH_PROBE_FILE"],
              !path.isEmpty else {
            return
        }

        hasRecordedFirstAppearance = true
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
