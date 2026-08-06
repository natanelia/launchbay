#if os(macOS)
    import AppKit
    import Foundation
    import LaunchBayCore

    extension AppModel {
        func startSystem() async -> Bool {
            let success =
                await perform("Start container system") {
                    try await self.client.startSystem()
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func stopSystem() async -> Bool {
            let success =
                await perform("Stop container system") {
                    try await self.client.stopSystem()
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func startContainer(_ container: ContainerSummary) async -> Bool {
            let success =
                await perform("Start \(container.name)") {
                    try await self.client.startContainer(id: container.id)
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func stopContainer(_ container: ContainerSummary) async -> Bool {
            let success =
                await perform("Stop \(container.name)") {
                    try await self.client.stopContainer(id: container.id)
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func deleteContainer(_ container: ContainerSummary, force: Bool = false) async -> Bool {
            let success =
                await perform("Delete \(container.name)") {
                    try await self.client.deleteContainer(id: container.id, force: force)
                } != nil
            await refreshAll(silent: true)
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
            await refreshAll(silent: true)
            return success
        }

        func pullImage(reference: String, platform: String?) async -> Bool {
            let success =
                await perform("Pull \(reference)") {
                    try await self.client.pullImage(reference: reference, platform: platform)
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func deleteImage(_ image: ImageSummary, force: Bool = false) async -> Bool {
            let success =
                await perform("Delete \(image.reference)") {
                    try await self.client.deleteImage(reference: image.reference, force: force)
                } != nil
            await refreshAll(silent: true)
            return success
        }

        func buildImage(_ configuration: BuildImageConfiguration) async -> Bool {
            let success =
                await perform("Build \(configuration.tag)") {
                    try await self.client.buildImage(configuration)
                } != nil
            await refreshAll(silent: true)
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

        func present(_ error: Error, title: String) {
            alertMessage = AlertMessage(title: title, message: error.localizedDescription)
        }
    }
#endif
