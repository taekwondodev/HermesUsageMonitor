import Foundation

struct HermesProfileQuotaSnapshotReader: ProfileQuotaSource, Sendable {
    private let hermesHome: URL
    private let now: @Sendable () -> Date

    init(
        hermesHome: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hermesHome = hermesHome
        self.now = now
    }

    func read() async -> [ProfileQuotaObservation] {
        let fileManager = FileManager.default
        let rootURL = hermesHome.appendingPathComponent(
            HermesQuotaSnapshotContract.relativePath
        )
        var candidates: [(HermesProfileID, URL)] = []

        if fileManager.fileExists(atPath: rootURL.path),
           let profile = try? HermesProfileID(value: "default") {
            candidates.append((profile, rootURL))
        }

        let profilesURL = hermesHome.appendingPathComponent("profiles", isDirectory: true)
        let directories = (try? fileManager.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for directory in directories.sorted(by: { $0.path < $1.path }) {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let profile = try? HermesProfileID(value: directory.lastPathComponent)
            else {
                continue
            }
            candidates.append((profile, directory.appendingPathComponent(
                HermesQuotaSnapshotContract.relativePath
            )))
        }

        return candidates.compactMap { profile, fileURL in
            guard case let .snapshot(snapshot) = HermesQuotaSnapshotReader(fileURL: fileURL).read(),
                  let observation = try? ProfileQuotaObservation(
                      profile: profile,
                      subscription: snapshot.subscription,
                      observedAt: QuotaTimestamp(date: now()),
                      result: .snapshot(snapshot)
                  )
            else {
                return nil
            }
            return observation
        }
    }
}
