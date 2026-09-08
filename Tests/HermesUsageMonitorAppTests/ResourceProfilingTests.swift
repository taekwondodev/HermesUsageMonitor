import Foundation
import Testing
@testable import HermesUsageMonitorApp

struct ResourceProfilingTests {
    @Test("accepts exactly fifteen seconds in both popover states")
    func acceptsCoverageBoundary() {
        let samples = [
            ResourceProfileSample(state: .open, footprintMegabytes: 10, cpuPercent: 2, durationSeconds: 15),
            ResourceProfileSample(state: .closed, footprintMegabytes: 8, cpuPercent: 1, durationSeconds: 15)
        ]

        #expect(ResourceProfileAggregator.result(for: samples).valid)
    }

    @Test("rejects a session that is short in either state")
    func rejectsInsufficientCoverage() {
        let samples = [
            ResourceProfileSample(state: .open, footprintMegabytes: 10, cpuPercent: 2, durationSeconds: 14.999),
            ResourceProfileSample(state: .closed, footprintMegabytes: 8, cpuPercent: 1, durationSeconds: 15)
        ]

        #expect(!ResourceProfileAggregator.result(for: samples).valid)
    }

    @Test("aggregates memory and CPU independently per state")
    func aggregatesMetrics() {
        let samples = [
            ResourceProfileSample(state: .open, footprintMegabytes: 10, cpuPercent: 2, durationSeconds: 8),
            ResourceProfileSample(state: .open, footprintMegabytes: 14, cpuPercent: 4, durationSeconds: 7),
            ResourceProfileSample(state: .closed, footprintMegabytes: 6, cpuPercent: 1, durationSeconds: 15)
        ]

        let result = ResourceProfileAggregator.result(for: samples)
        #expect(result.aggregates.open == ResourceProfileAggregate(
            sampleCount: 2,
            durationSeconds: 15,
            memoryAverageMegabytes: 12,
            memoryPeakMegabytes: 14,
            cpuAveragePercent: 3
        ))
        #expect(result.aggregates.closed == ResourceProfileAggregate(
            sampleCount: 1,
            durationSeconds: 15,
            memoryAverageMegabytes: 6,
            memoryPeakMegabytes: 6,
            cpuAveragePercent: 1
        ))
    }

    @Test("computes CPU percentage from injected process-time deltas")
    func computesCPUPercentage() {
        let previous = ProcessResourceMetrics(footprintBytes: 1, cpuTimeSeconds: 4)
        let current = ProcessResourceMetrics(footprintBytes: 1, cpuTimeSeconds: 4.5)

        #expect(ProcessResourceSampleReader.cpuPercent(previous: previous, current: current, duration: 2) == 25)
        #expect(ProcessResourceSampleReader.cpuPercent(previous: previous, current: current, duration: 0) == 0)
    }

    @Test("inactive environment keeps the sampler unarmed")
    func inactiveGate() {
        #expect(!ResourceSamplerCoordinator.isArmed(environment: [:]))
        #expect(!ResourceSamplerCoordinator.isArmed(environment: [ResourceSamplerCoordinator.environmentKey: ""]))
        #expect(ResourceSamplerCoordinator.isArmed(environment: [ResourceSamplerCoordinator.environmentKey: "/tmp/profile.json"]))
    }

    @Test("resource payload contains aggregates and samples but no quota fields")
    func payloadShape() throws {
        let result = ResourceProfileAggregator.result(for: [
            ResourceProfileSample(state: .open, footprintMegabytes: 10, cpuPercent: 2, durationSeconds: 15),
            ResourceProfileSample(state: .closed, footprintMegabytes: 8, cpuPercent: 1, durationSeconds: 15)
        ])
        let data = try JSONEncoder().encode(result)
        let json = String(decoding: data, as: UTF8.self)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["aggregates"] is [String: Any])
        #expect(json.contains("aggregates"))
        #expect(json.contains("samples"))
        #expect(!json.contains("quota"))
        #expect(!json.contains("credential"))
        #expect(!json.contains("provider"))
    }
}
