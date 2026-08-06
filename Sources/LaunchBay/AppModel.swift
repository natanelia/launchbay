#if os(macOS)
    import AppKit
    import Foundation
    import LaunchBayCore
    import SwiftUI

    @MainActor
    final class AppModel: ObservableObject {
        enum Section: String, CaseIterable, Identifiable {
            case dashboard
            case containers
            case images
            case activity
            case settings

            var id: String { rawValue }

            var title: String {
                switch self {
                case .dashboard: "Dashboard"
                case .containers: "Containers"
                case .images: "Images"
                case .activity: "Activity"
                case .settings: "Settings"
                }
            }

            var systemImage: String {
                switch self {
                case .dashboard: "square.grid.2x2"
                case .containers: "shippingbox"
                case .images: "opticaldiscdrive"
                case .activity: "terminal"
                case .settings: "gearshape"
                }
            }
        }

        struct AlertMessage: Identifiable {
            let id = UUID()
            let title: String
            let message: String
        }

        struct ActivityEntry: Identifiable, Hashable {
            enum Outcome: Hashable {
                case succeeded
                case failed
            }

            let id = UUID()
            let date: Date
            let title: String
            let command: String
            let standardOutput: String
            let standardError: String
            let exitCode: Int32?
            let durationSeconds: TimeInterval?
            let outcome: Outcome
        }

        @Published var selectedSection: Section? = .dashboard
        @Published private(set) var hostCompatibility = HostCompatibility.detect()
        @Published private(set) var executablePath: String?
        @Published private(set) var systemStatus = ContainerSystemStatus.unavailable
        @Published private(set) var containers: [ContainerSummary] = []
        @Published private(set) var images: [ImageSummary] = []
        @Published private(set) var activities: [ActivityEntry] = []
        @Published private(set) var isRefreshing = false
        @Published private(set) var activeOperation: String?
        @Published var alertMessage: AlertMessage?
        @Published var presentRunContainer = false
        @Published var presentPullImage = false
        @Published var presentBuildImage = false
        @Published private(set) var requestedRunImageReference = ""

        @Published var customExecutablePath: String {
            didSet {
                defaults.set(customExecutablePath, forKey: DefaultsKey.customExecutablePath)
            }
        }

        @Published var autoRefreshSeconds: Double {
            didSet {
                defaults.set(autoRefreshSeconds, forKey: DefaultsKey.autoRefreshSeconds)
            }
        }

        private enum DefaultsKey {
            static let customExecutablePath = "customContainerCLIPath"
            static let autoRefreshSeconds = "autoRefreshSeconds"
        }

        private let defaults: UserDefaults
        private let client: ContainerCLI
        private let refreshCadence: RefreshCadence
        private var autoRefreshTask: Task<Void, Never>?
        private var hasBootstrapped = false
        private var isApplicationActive = true

        init(
            defaults: UserDefaults = .standard,
            client: ContainerCLI = ContainerCLI(),
            refreshCadence: RefreshCadence = RefreshCadence()
        ) {
            self.defaults = defaults
            self.client = client
            self.refreshCadence = refreshCadence
            self.customExecutablePath =
                defaults.string(forKey: DefaultsKey.customExecutablePath) ?? ""

            if defaults.object(forKey: DefaultsKey.autoRefreshSeconds) != nil {
                self.autoRefreshSeconds = defaults.double(forKey: DefaultsKey.autoRefreshSeconds)
            } else {
                self.autoRefreshSeconds = 5
            }
        }

        var isCLIInstalled: Bool { executablePath != nil }
        var isSystemRunning: Bool { systemStatus.state == .running }
        var canManageResources: Bool { isCLIInstalled && isSystemRunning && activeOperation == nil }
        var runningContainerCount: Int { containers.filter { $0.state == .running }.count }

        func bootstrap() async {
            hostCompatibility = .detect()
            let locator = ContainerExecutableLocator()
            let explicitPath = customExecutablePath.trimmed.isEmpty ? nil : customExecutablePath.trimmed
            let executableURL = locator.locate(explicitPath: explicitPath)
            executablePath = executableURL?.path
            await client.configure(executableURL: executableURL)
            hasBootstrapped = true
            await refreshAll(silent: true)
            restartAutoRefresh()
        }

        func refreshAll(silent: Bool = false, force: Bool = false) async {
            guard hasBootstrapped else { return }
            if force { await client.invalidateReadCache() }
            if !silent { isRefreshing = true }
            defer { if !silent { isRefreshing = false } }

            guard isCLIInstalled else {
                systemStatus = .unavailable
                containers = []
                images = []
                return
            }

            do {
                let status = try await client.systemStatus()
                systemStatus = status.value
            } catch {
                systemStatus = ContainerSystemStatus(state: .unknown)
                if !silent { present(error, title: "Could not read system status") }
                return
            }

            guard systemStatus.state == .running else {
                containers = []
                images = []
                return
            }

            let containerRequest = Task {
                try await client.listContainers(includeStopped: true)
            }
            let imageRequest = Task {
                try await client.listImages()
            }

            do {
                let executed = try await containerRequest.value
                containers = executed.value.sorted {
                    if $0.state != $1.state { return $0.state == .running }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            } catch {
                if !silent { present(error, title: "Could not list containers") }
            }

            do {
                let executed = try await imageRequest.value
                images = executed.value.sorted {
                    $0.reference.localizedCaseInsensitiveCompare($1.reference) == .orderedAscending
                }
            } catch {
                if !silent { present(error, title: "Could not list images") }
            }
        }

        func startSystem() async -> Bool {
            let success =
                await perform("Start container system") {
                    try await self.client.startSystem()
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func stopSystem() async -> Bool {
            let success =
                await perform("Stop container system") {
                    try await self.client.stopSystem()
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func startContainer(_ container: ContainerSummary) async -> Bool {
            let success =
                await perform("Start \(container.name)") {
                    try await self.client.startContainer(id: container.id)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func stopContainer(_ container: ContainerSummary) async -> Bool {
            let success =
                await perform("Stop \(container.name)") {
                    try await self.client.stopContainer(id: container.id)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func deleteContainer(_ container: ContainerSummary, force: Bool = false) async -> Bool {
            let success =
                await perform("Delete \(container.name)") {
                    try await self.client.deleteContainer(id: container.id, force: force)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func fetchLogs(for container: ContainerSummary, boot: Bool = false) async -> String? {
            await perform("Read logs for \(container.name)", recordSuccess: false) {
                try await self.client.containerLogs(id: container.id, tail: 500, boot: boot)
            }?.value
        }

        func runContainer(_ configuration: RunContainerConfiguration) async -> Bool {
            let title =
                configuration.name.trimmed.isEmpty
                ? "Run \(configuration.imageReference)"
                : "Run \(configuration.name)"
            let success =
                await perform(title) {
                    try await self.client.runContainer(configuration)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func pullImage(reference: String, platform: String?) async -> Bool {
            let success =
                await perform("Pull \(reference)") {
                    try await self.client.pullImage(reference: reference, platform: platform)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func deleteImage(_ image: ImageSummary, force: Bool = false) async -> Bool {
            let success =
                await perform("Delete \(image.reference)") {
                    try await self.client.deleteImage(reference: image.reference, force: force)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func buildImage(_ configuration: BuildImageConfiguration) async -> Bool {
            let success =
                await perform("Build \(configuration.tag)") {
                    try await self.client.buildImage(configuration)
                } != nil
            if success { await refreshAll(silent: true) }
            return success
        }

        func requestRunContainer(imageReference: String? = nil) {
            requestedRunImageReference = imageReference?.trimmed ?? ""
            presentRunContainer = true
        }

        func clearRunContainerRequest() {
            requestedRunImageReference = ""
        }

        func updateExecutablePath(_ path: String) async {
            customExecutablePath = path
            await bootstrap()
        }

        func resetExecutablePath() async {
            customExecutablePath = ""
            await bootstrap()
        }

        func setApplicationActive(_ isActive: Bool) {
            guard isApplicationActive != isActive else { return }
            isApplicationActive = isActive

            if isActive {
                autoRefreshTask?.cancel()
                autoRefreshTask = nil
                Task { [weak self] in
                    guard let self else { return }
                    await refreshAll(silent: true, force: true)
                    restartAutoRefresh()
                }
            } else {
                autoRefreshTask?.cancel()
                autoRefreshTask = nil
            }
        }

        func restartAutoRefresh() {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
            guard isApplicationActive, autoRefreshSeconds > 0 else { return }

            autoRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let interval = refreshCadence.interval(
                        baseInterval: autoRefreshSeconds,
                        systemState: systemStatus.state,
                        runningContainerCount: runningContainerCount
                    )
                    guard interval > 0 else { return }
                    let nanoseconds = UInt64(interval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    if activeOperation == nil {
                        await refreshAll(silent: true)
                    }
                }
            }
        }

        func copyShellCommand(for container: ContainerSummary) {
            guard let executablePath else { return }
            let invocation = CommandInvocation(
                executableURL: URL(fileURLWithPath: executablePath),
                arguments: ["exec", "--interactive", "--tty", container.id, "/bin/sh"]
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(invocation.redactedDisplayCommand, forType: .string)
        }

        func clearActivity() {
            activities.removeAll()
        }

        private func perform<Value: Sendable>(
            _ title: String,
            recordSuccess: Bool = true,
            operation: () async throws -> Executed<Value>
        ) async -> Executed<Value>? {
            guard activeOperation == nil else { return nil }
            activeOperation = title
            defer { activeOperation = nil }

            do {
                let executed = try await operation()
                if recordSuccess {
                    record(title: title, result: executed.result, outcome: .succeeded)
                }
                return executed
            } catch {
                if case ContainerCLIError.commandFailed(let result) = error {
                    record(title: title, result: result, outcome: .failed)
                } else {
                    activities.insert(
                        ActivityEntry(
                            date: Date(),
                            title: title,
                            command: "",
                            standardOutput: "",
                            standardError: error.localizedDescription,
                            exitCode: nil,
                            durationSeconds: nil,
                            outcome: .failed
                        ),
                        at: 0
                    )
                }
                trimActivity()
                present(error, title: title)
                return nil
            }
        }

        private func record(title: String, result: CommandResult, outcome: ActivityEntry.Outcome) {
            activities.insert(
                ActivityEntry(
                    date: Date(),
                    title: title,
                    command: result.invocation.redactedDisplayCommand,
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    exitCode: result.exitCode,
                    durationSeconds: result.durationSeconds,
                    outcome: outcome
                ),
                at: 0
            )
            trimActivity()
        }

        private func trimActivity() {
            if activities.count > 100 {
                activities.removeLast(activities.count - 100)
            }
        }

        private func present(_ error: Error, title: String) {
            alertMessage = AlertMessage(title: title, message: error.localizedDescription)
        }
    }
#endif
