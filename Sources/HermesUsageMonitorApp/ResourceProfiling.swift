import AppKit
import Darwin
import Foundation

enum ResourceProfileState: String, Codable, CaseIterable, Sendable {
    case open
    case closed
}

struct ResourceProfileSample: Codable, Equatable, Sendable {
    let state: ResourceProfileState
    let footprintMegabytes: Double
    let cpuPercent: Double
    let durationSeconds: Double
}

struct ResourceProfileAggregate: Codable, Equatable, Sendable {
    let sampleCount: Int
    let durationSeconds: Double
    let memoryAverageMegabytes: Double
    let memoryPeakMegabytes: Double
    let cpuAveragePercent: Double
}

struct ResourceProfileAggregates: Codable, Equatable, Sendable {
    let open: ResourceProfileAggregate
    let closed: ResourceProfileAggregate
}

struct ResourceProfileResult: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let valid: Bool
    let coverageThresholdSeconds: Double
    let samples: [ResourceProfileSample]
    let aggregates: ResourceProfileAggregates
}

enum ResourceProfileAggregator {
    static let coverageThresholdSeconds = 15.0

    static func result(for samples: [ResourceProfileSample]) -> ResourceProfileResult {
        let aggregates = ResourceProfileAggregates(
            open: aggregate(samples.filter { $0.state == .open }),
            closed: aggregate(samples.filter { $0.state == .closed })
        )
        let valid = ResourceProfileState.allCases.allSatisfy {
            switch $0 {
            case .open: aggregates.open.durationSeconds >= coverageThresholdSeconds
            case .closed: aggregates.closed.durationSeconds >= coverageThresholdSeconds
            }
        }
        return ResourceProfileResult(
            schemaVersion: 1,
            valid: valid,
            coverageThresholdSeconds: coverageThresholdSeconds,
            samples: samples,
            aggregates: aggregates
        )
    }

    private static func aggregate(_ samples: [ResourceProfileSample]) -> ResourceProfileAggregate {
        guard !samples.isEmpty else {
            return ResourceProfileAggregate(
                sampleCount: 0,
                durationSeconds: 0,
                memoryAverageMegabytes: 0,
                memoryPeakMegabytes: 0,
                cpuAveragePercent: 0
            )
        }
        return ResourceProfileAggregate(
            sampleCount: samples.count,
            durationSeconds: samples.reduce(0) { $0 + $1.durationSeconds },
            memoryAverageMegabytes: samples.map(\.footprintMegabytes).reduce(0, +) / Double(samples.count),
            memoryPeakMegabytes: samples.map(\.footprintMegabytes).max()!,
            cpuAveragePercent: samples.map(\.cpuPercent).reduce(0, +) / Double(samples.count)
        )
    }
}

struct ProcessResourceMetrics: Sendable {
    let footprintBytes: UInt64
    let cpuTimeSeconds: Double
}

struct ProcessResourceSampleReader {
    private var previous: ProcessResourceMetrics?
    private var previousUptime: TimeInterval?

    mutating func read(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (footprintMegabytes: Double, cpuPercent: Double, durationSeconds: Double)? {
        guard let current = Self.readCurrentMetrics() else { return nil }
        let duration = uptime - (previousUptime ?? uptime)
        let cpuPercent = Self.cpuPercent(previous: previous, current: current, duration: duration)
        previous = current
        previousUptime = uptime
        return (
            Double(current.footprintBytes) / 1_048_576,
            cpuPercent,
            max(0, duration)
        )
    }

    static func cpuPercent(
        previous: ProcessResourceMetrics?,
        current: ProcessResourceMetrics,
        duration: TimeInterval
    ) -> Double {
        guard let previous, duration > 0 else { return 0 }
        return max(0, (current.cpuTimeSeconds - previous.cpuTimeSeconds) / duration * 100)
    }

    private static func readCurrentMetrics() -> ProcessResourceMetrics? {
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: vmInfo) / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        guard vmResult == KERN_SUCCESS else { return nil }

        var times = task_thread_times_info_data_t()
        var timeCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: times) / MemoryLayout<integer_t>.size)
        let timeResult = withUnsafeMutablePointer(to: &times) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(timeCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &timeCount)
            }
        }
        guard timeResult == KERN_SUCCESS else { return nil }
        let cpuSeconds = Double(times.user_time.seconds) + Double(times.user_time.microseconds) / 1_000_000
            + Double(times.system_time.seconds) + Double(times.system_time.microseconds) / 1_000_000
        return ProcessResourceMetrics(
            footprintBytes: UInt64(vmInfo.phys_footprint),
            cpuTimeSeconds: cpuSeconds
        )
    }
}

@MainActor
final class ResourceSamplerCoordinator {
    nonisolated static let environmentKey = "HERMES_RESOURCE_PROFILE_FILE"
    nonisolated static let cadenceNanoseconds: UInt64 = 500_000_000

    private let destination: URL?
    private var task: Task<Void, Never>?
    private var samples: [ResourceProfileSample] = []
    private var isPopoverVisible = false
    private var reader = ProcessResourceSampleReader()
    private var terminationObserver: NSObjectProtocol?

    init(environment: [String: String]? = nil) {
        if let environment {
            guard let rawPath = environment[Self.environmentKey], !rawPath.isEmpty else {
                destination = nil
                return
            }
            destination = URL(fileURLWithPath: rawPath)
            return
        }
        guard let rawPath = getenv(Self.environmentKey),
              let path = String(validatingCString: rawPath),
              !path.isEmpty else {
            destination = nil
            return
        }
        destination = URL(fileURLWithPath: path)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopAndPersist()
            }
        }
    }

    var isArmed: Bool { destination != nil }

    func start() {
        guard destination != nil, task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.cadenceNanoseconds)
                guard !Task.isCancelled else { return }
                self?.capture()
            }
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
    }

    func stopAndPersist() {
        task?.cancel()
        task = nil
        guard let destination else { return }
        let result = ResourceProfileAggregator.result(for: samples)
        guard let data = try? JSONEncoder.pretty.encode(result) else { return }
        ResourceProfileWriter.write(data, to: destination)
    }

    private func capture() {
        guard let reading = reader.read() else { return }
        samples.append(ResourceProfileSample(
            state: isPopoverVisible ? .open : .closed,
            footprintMegabytes: reading.footprintMegabytes,
            cpuPercent: reading.cpuPercent,
            durationSeconds: reading.durationSeconds
        ))
    }
}

private enum ResourceProfileWriter {
    static func write(_ data: Data, to destination: URL) {
        try? data.write(to: destination, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension ResourceSamplerCoordinator {
    nonisolated static func isArmed(environment: [String: String]) -> Bool {
        guard let path = environment[environmentKey] else { return false }
        return !path.isEmpty
    }
}
