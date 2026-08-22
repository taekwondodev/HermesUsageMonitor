protocol ProfileUsageSource: Sendable {
    func readUsage() async -> ProfileUsageRead
}
