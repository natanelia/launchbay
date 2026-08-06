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
        @Published var hostCompatibility = HostCompatibility.detect()
        @Published var executablePath: String?
        @Published var systemStatus = ContainerSystemStatus.unavailable
        @Published var containers: [ContainerSummary] = []
        @Published var images: [ImageSummary] = []
        @Published var activities: [ActivityEntry] = []
        @Published var isRefreshing = false
        @Published var activeOperation: String?
        @Published var alertMessage: AlertMessage?
        @Published var presentRunContainer = false
        @Published var presentPullImage = false
        @Published var presentBuildImage = false
        @Published var requestedRunImageReference = ""

        @Published var customExecutablePath: String {
            didSet {
                defaults.set(customExecutablePath, forKey: DefaultsKey.customExecutablePath)
            }
        }

        @Published var autoRefreshSeconds: Double {
            didSet {
                defaults.set(autoRefreshSeconds, forKey: DefaultsKey.autoRefreshSeconds)
                if hasBootstrapped {
                    restartAutoRefresh()
                }
            }
        }

        private enum DefaultsKey {
            static let customExecutablePath = "customContainerCLIPath"
            static let autoRefreshSeconds = "autoRefreshSeconds"
        }

        private let defaults: UserDefaults
        let client: ContainerCLI
        let refreshCadence: RefreshCadence
        let refreshSleep: @Sendable (TimeInterval) async throws -> Void
        var autoRefreshTask: Task<Void, Never>?
        var autoRefreshScheduleGeneration: UInt64 = 0
        var hasBootstrapped = false
        var isApplicationActive = false
        var lifecycleGeneration: UInt64 = 0
        var refreshGeneration: UInt64 = 0
        var visibleRefreshID: UUID?

        var scheduledAutoRefreshInterval: TimeInterval?

        init(
            defaults: UserDefaults = .standard,
            client: ContainerCLI = ContainerCLI(),
            refreshCadence: RefreshCadence = RefreshCadence(),
            refreshSleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
                try await Task<Never, Never>.sleep(for: .seconds(interval))
            }
        ) {
            self.defaults = defaults
            self.client = client
            self.refreshCadence = refreshCadence
            self.refreshSleep = refreshSleep
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
    }
#endif
