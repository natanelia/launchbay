#if os(macOS)
    import Foundation
    import LaunchBayCore

    extension AppModel {
        func handleApplicationActive(_ isActive: Bool) async {
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration

            if !hasBootstrapped {
                isApplicationActive = isActive
                await bootstrap(lifecycleGeneration: generation)
                return
            }
            await applyApplicationActive(isActive, lifecycleGeneration: generation)
        }

        func bootstrap() async {
            lifecycleGeneration &+= 1
            await bootstrap(lifecycleGeneration: lifecycleGeneration)
        }

        private func bootstrap(lifecycleGeneration generation: UInt64) async {
            cancelAutoRefresh()
            refreshGeneration &+= 1
            await client.cancelPendingReads()
            guard shouldContinueLifecycle(generation: generation) else { return }

            let compatibility = HostCompatibility.detect()
            let locator = ContainerExecutableLocator()
            let explicitPath = customExecutablePath.trimmed.isEmpty ? nil : customExecutablePath.trimmed
            let executableURL = locator.locate(explicitPath: explicitPath)
            guard shouldContinueLifecycle(generation: generation) else { return }

            hostCompatibility = compatibility
            executablePath = executableURL?.path
            await client.configure(executableURL: executableURL)
            guard shouldContinueLifecycle(generation: generation) else { return }
            hasBootstrapped = true

            guard isApplicationActive else {
                systemStatus = .unavailable
                containers = []
                images = []
                return
            }

            await refreshAll(silent: true, force: true)
            guard shouldContinueLifecycle(generation: generation), isApplicationActive else { return }
            restartAutoRefresh()
        }

        func refreshAll(silent: Bool = false, force: Bool = false) async {
            guard hasBootstrapped, isApplicationActive else { return }

            refreshGeneration &+= 1
            let generation = refreshGeneration
            let cadenceBefore = automaticRefreshInterval
            let hadScheduledRefresh = scheduledAutoRefreshInterval != nil
            let progressID = silent ? nil : UUID()
            if let progressID {
                visibleRefreshID = progressID
                isRefreshing = true
            }
            defer {
                if let progressID, visibleRefreshID == progressID {
                    visibleRefreshID = nil
                    isRefreshing = false
                }
                if hadScheduledRefresh,
                    shouldContinueRefresh(generation: generation),
                    cadenceBefore != automaticRefreshInterval
                {
                    restartAutoRefresh()
                }
            }

            if force {
                await client.cancelPendingReads()
                guard shouldContinueRefresh(generation: generation) else { return }
                await client.invalidateReadCache()
                guard shouldContinueRefresh(generation: generation) else { return }
            }

            guard isCLIInstalled else {
                systemStatus = .unavailable
                containers = []
                images = []
                return
            }

            do {
                let status = try await client.systemStatus()
                guard shouldContinueRefresh(generation: generation) else { return }
                systemStatus = status.value
            } catch {
                guard shouldContinueRefresh(generation: generation) else { return }
                systemStatus = ContainerSystemStatus(state: .unknown)
                if !silent { present(error, title: "Could not read system status") }
                return
            }

            guard shouldContinueRefresh(generation: generation) else { return }
            guard systemStatus.state == .running else {
                containers = []
                images = []
                return
            }

            async let containerRequest = client.listContainers(includeStopped: true)
            async let imageRequest = client.listImages()

            do {
                let executed = try await containerRequest
                guard shouldContinueRefresh(generation: generation) else { return }
                containers = executed.value.sorted {
                    if $0.state != $1.state { return $0.state == .running }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            } catch {
                guard shouldContinueRefresh(generation: generation) else { return }
                if !silent { present(error, title: "Could not list containers") }
            }

            do {
                let executed = try await imageRequest
                guard shouldContinueRefresh(generation: generation) else { return }
                images = executed.value.sorted {
                    $0.reference.localizedCaseInsensitiveCompare($1.reference) == .orderedAscending
                }
            } catch {
                guard shouldContinueRefresh(generation: generation) else { return }
                if !silent { present(error, title: "Could not list images") }
            }
        }
        func setApplicationActive(_ isActive: Bool) async {
            lifecycleGeneration &+= 1
            await applyApplicationActive(isActive, lifecycleGeneration: lifecycleGeneration)
        }

        private func applyApplicationActive(
            _ isActive: Bool,
            lifecycleGeneration generation: UInt64
        ) async {
            guard shouldContinueLifecycle(generation: generation) else { return }
            guard isApplicationActive != isActive else {
                if isActive {
                    restartAutoRefresh()
                }
                return
            }

            isApplicationActive = isActive
            refreshGeneration &+= 1
            cancelAutoRefresh()

            guard isActive else {
                await client.cancelPendingReads()
                return
            }
            guard hasBootstrapped else { return }

            await refreshAll(silent: true, force: true)
            guard shouldContinueLifecycle(generation: generation), isApplicationActive else { return }
            restartAutoRefresh()
        }

        func restartAutoRefresh() {
            cancelAutoRefresh()
            guard hasBootstrapped, isApplicationActive, autoRefreshSeconds > 0 else { return }

            let interval = automaticRefreshInterval
            guard interval > 0 else { return }
            scheduledAutoRefreshInterval = interval
            let scheduleGeneration = autoRefreshScheduleGeneration
            let refreshSleep = refreshSleep

            autoRefreshTask = Task { [weak self] in
                do {
                    try await refreshSleep(interval)
                } catch {
                    return
                }

                guard let self,
                    shouldRunScheduledRefresh(generation: scheduleGeneration)
                else {
                    return
                }

                if activeOperation == nil, !isRefreshing {
                    await refreshAll(silent: true)
                }

                guard shouldRunScheduledRefresh(generation: scheduleGeneration) else { return }
                restartAutoRefresh()
            }
        }
        private var automaticRefreshInterval: TimeInterval {
            refreshCadence.interval(
                baseInterval: autoRefreshSeconds,
                systemState: systemStatus.state,
                runningContainerCount: runningContainerCount
            )
        }

        private func shouldContinueLifecycle(generation: UInt64) -> Bool {
            !Task.isCancelled && generation == lifecycleGeneration
        }

        private func shouldContinueRefresh(generation: UInt64) -> Bool {
            !Task.isCancelled && isApplicationActive && generation == refreshGeneration
        }

        private func shouldRunScheduledRefresh(generation: UInt64) -> Bool {
            !Task.isCancelled
                && isApplicationActive
                && generation == autoRefreshScheduleGeneration
        }

        private func cancelAutoRefresh() {
            autoRefreshScheduleGeneration &+= 1
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
            scheduledAutoRefreshInterval = nil
        }
    }
#endif
