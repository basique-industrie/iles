import Darwin
import Domain
import Foundation
import Network

@MainActor
final class MacSystemComplicationSource: ComplicationSource {
    private struct StorageUsage {
        let percentUsed: Double
        let percentAvailable: Double
        let freeLabel: String
    }

    private struct NetworkState: Sendable {
        let available: Bool
        let interface: String
        let constrained: Bool
        let expensive: Bool

        static let unknown = NetworkState(
            available: false,
            interface: "Checking",
            constrained: false,
            expensive: false
        )
    }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.jean.iles.network-path", qos: .utility)
    private var networkState = NetworkState.unknown
    private var cachedSnapshot: SourceSnapshot?
    private var previousCPUTicks: (used: UInt64, total: UInt64)?
    private var smoothedCPUUsage: Double?
    private var cachedStorageUsage: StorageUsage?
    private var storageUsageCapturedAt: Date?

    let descriptor = ComplicationSourceDescriptor(
        id: "system.mac",
        name: "Mac Health",
        kind: .system,
        symbol: "macbook",
        metrics: [
            ComplicationMetricDescriptor(
                id: "cpu",
                name: "CPU usage",
                kind: .gauge,
                symbol: "cpu",
                unit: "%",
                policy: ComplicationMetricPolicy(
                    format: .percentage,
                    direction: .lowerIsBetter,
                    range: 0...100,
                    thresholds: ComplicationThreshold(warning: 75, critical: 90),
                    refreshClass: .liveLocal,
                    staleAfter: 10,
                    keepsHistory: true
                )
            ),
            ComplicationMetricDescriptor(
                id: "memory",
                name: "Memory load",
                kind: .gauge,
                symbol: "memorychip",
                unit: "%",
                policy: ComplicationMetricPolicy(
                    format: .percentage,
                    direction: .lowerIsBetter,
                    range: 0...100,
                    thresholds: ComplicationThreshold(warning: 75, critical: 90),
                    refreshClass: .liveLocal,
                    staleAfter: 10,
                    keepsHistory: true
                )
            ),
            ComplicationMetricDescriptor(
                id: "storage",
                name: "Storage used",
                kind: .gauge,
                symbol: "internaldrive",
                unit: "%",
                policy: ComplicationMetricPolicy(
                    format: .percentage,
                    direction: .lowerIsBetter,
                    range: 0...100,
                    thresholds: ComplicationThreshold(warning: 80, critical: 92),
                    refreshClass: .periodicLocal,
                    staleAfter: 300
                )
            ),
            ComplicationMetricDescriptor(
                id: "storageAvailable",
                name: "Storage available",
                kind: .gauge,
                symbol: "internaldrive",
                unit: "%",
                policy: ComplicationMetricPolicy(
                    format: .percentage,
                    direction: .higherIsBetter,
                    range: 0...100,
                    thresholds: ComplicationThreshold(warning: 20, critical: 8),
                    refreshClass: .periodicLocal,
                    staleAfter: 300
                )
            ),
            ComplicationMetricDescriptor(id: "storageFree", name: "Storage free", kind: .value, symbol: "internaldrive", policy: ComplicationMetricPolicy(format: .bytes)),
            ComplicationMetricDescriptor(id: "network", name: "Network state", kind: .status, symbol: "network", policy: ComplicationMetricPolicy(format: .status, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "networkType", name: "Connection type", kind: .value, symbol: "wifi", policy: ComplicationMetricPolicy(format: .text, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "thermal", name: "Thermal state", kind: .status, symbol: "thermometer.high", policy: ComplicationMetricPolicy(format: .status, direction: .lowerIsBetter, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "lowPower", name: "Low Power Mode", kind: .status, symbol: "leaf", policy: ComplicationMetricPolicy(format: .status, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "uptime", name: "System uptime", kind: .duration, symbol: "power", policy: ComplicationMetricPolicy(format: .duration, refreshClass: .periodicLocal)),
        ],
        supportedFamilies: [.ring, .dualRing, .value, .status, .activity, .trend, .summary, .cluster],
        complications: FirstPartyComplicationCatalog.macSystemRecipes,
        capabilities: [.systemHealth, .shortHistory]
    )

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = Self.networkState(from: path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkState = state
                self.cachedSnapshot = nil
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    var currentSnapshot: SourceSnapshot {
        if let cachedSnapshot,
           Date().timeIntervalSince(cachedSnapshot.capturedAt) < 2 {
            return cachedSnapshot
        }
        let snapshot = makeSnapshot()
        cachedSnapshot = snapshot
        return snapshot
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        cachedSnapshot = nil
        return currentSnapshot
    }

    private func makeSnapshot(at date: Date = Date()) -> SourceSnapshot {
        let process = ProcessInfo.processInfo
        var values: [String: ComplicationValue] = [
            "network": .status(
                label: networkState.available ? "Online" : "Offline",
                level: networkState.available ? .healthy : .critical
            ),
            "networkType": .value(networkLabel, unit: nil),
            "thermal": thermalValue(process.thermalState),
            "lowPower": .status(
                label: process.isLowPowerModeEnabled ? "On" : "Off",
                level: process.isLowPowerModeEnabled ? .warning : .healthy
            ),
            "uptime": .duration(process.systemUptime, label: Self.durationLabel(process.systemUptime)),
        ]

        if let cpu = cpuUsage() {
            values["cpu"] = .gauge(value: cpu, range: 0...100, label: "\(Int(cpu.rounded()))%")
        }
        if let memory = Self.memoryUsage() {
            values["memory"] = .gauge(value: memory, range: 0...100, label: "\(Int(memory.rounded()))%")
        }
        if let storage = storageUsage(at: date) {
            values["storage"] = .gauge(
                value: storage.percentUsed,
                range: 0...100,
                label: "\(Int(storage.percentUsed.rounded()))%"
            )
            values["storageAvailable"] = .gauge(
                value: storage.percentAvailable,
                range: 0...100,
                label: "\(Int(storage.percentAvailable.rounded()))%"
            )
            values["storageFree"] = .value(storage.freeLabel, unit: nil)
        }

        return SourceSnapshot(sourceID: descriptor.id, capturedAt: date, values: values)
    }

    private var networkLabel: String {
        var details = networkState.interface
        if networkState.constrained { details += " · Low Data" }
        if networkState.expensive { details += " · Metered" }
        return details
    }

    private func thermalValue(_ state: ProcessInfo.ThermalState) -> ComplicationValue {
        switch state {
        case .nominal: .status(label: "Nominal", level: .healthy)
        case .fair: .status(label: "Warm", level: .warning)
        case .serious: .status(label: "Hot", level: .critical)
        case .critical: .status(label: "Critical", level: .critical)
        @unknown default: .status(label: "Unknown", level: .inactive)
        }
    }

    private func cpuUsage() -> Double? {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &count
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let buffer = UnsafeBufferPointer(start: info, count: Int(count))
        var used: UInt64 = 0
        var total: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * stride
            let user = UInt64(buffer[offset + Int(CPU_STATE_USER)])
            let system = UInt64(buffer[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(buffer[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(buffer[offset + Int(CPU_STATE_IDLE)])
            used += user + system + nice
            total += user + system + nice + idle
        }

        let sample: Double
        if let previousCPUTicks,
           total > previousCPUTicks.total,
           used >= previousCPUTicks.used {
            let usedDelta = used - previousCPUTicks.used
            let totalDelta = total - previousCPUTicks.total
            sample = min(max(Double(usedDelta) / Double(totalDelta) * 100, 0), 100)
        } else {
            var load = [Double](repeating: 0, count: 1)
            guard getloadavg(&load, 1) == 1 else { return nil }
            sample = min(max(load[0] / Double(max(ProcessInfo.processInfo.processorCount, 1)) * 100, 0), 100)
        }
        previousCPUTicks = (used, total)
        let smoothed = smoothedCPUUsage.map { previous in
            previous * 0.65 + sample * 0.35
        } ?? sample
        smoothedCPUUsage = smoothed
        return smoothed
    }

    private static func memoryUsage() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = Double(getpagesize())
        // Inactive/cache pages are intentionally reclaimable on macOS. Counting
        // them as pressure makes a healthy Mac look permanently full, so the
        // glance tracks active, wired, and compressed working memory instead.
        let usedPages = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = usedPages * pageSize
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }
        return min(max(usedBytes / totalBytes * 100, 0), 100)
    }

    private func storageUsage(at date: Date) -> StorageUsage? {
        if let storageUsageCapturedAt,
           date.timeIntervalSince(storageUsageCapturedAt) < 60 {
            return cachedStorageUsage
        }
        let storage = Self.readStorageUsage()
        cachedStorageUsage = storage
        storageUsageCapturedAt = date
        return storage
    }

    private static func readStorageUsage() -> StorageUsage? {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
        let total = values.volumeTotalCapacity,
        let free = values.volumeAvailableCapacityForImportantUsage,
        total > 0
        else { return nil }
        let percentAvailable = min(max(Double(free) / Double(total) * 100, 0), 100)
        return StorageUsage(
            percentUsed: 100 - percentAvailable,
            percentAvailable: percentAvailable,
            freeLabel: ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        )
    }

    private nonisolated static func networkState(from path: NWPath) -> NetworkState {
        let interface: String
        if path.usesInterfaceType(.wifi) {
            interface = "Wi-Fi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = "Ethernet"
        } else if path.usesInterfaceType(.cellular) {
            interface = "Cellular"
        } else if path.usesInterfaceType(.loopback) {
            interface = "Local"
        } else {
            interface = path.status == .satisfied ? "Other" : "Offline"
        }
        return NetworkState(
            available: path.status == .satisfied,
            interface: interface,
            constrained: path.isConstrained,
            expensive: path.isExpensive
        )
    }

    private static func durationLabel(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86_400
        if days > 0 { return "\(days)d" }
        let hours = Int(interval) / 3_600
        return "\(hours)h"
    }
}
