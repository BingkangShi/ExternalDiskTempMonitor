import Cocoa
import DiskArbitration

// MARK: - Clickable View (for floating window click handling)

// MARK: - App Delegate

class DiskTempMonitor: NSObject, NSApplicationDelegate {
    // Display — status item (right side of menu bar)
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!

    // Disk tracking
    private var timer: Timer?
    private var externalDisks: Set<String> = []
    private var diskTemps: [String: String] = [:]
    private var diskModes: [String: String] = [:]
    private var diskModels: [String: String] = [:]
    private var daSession: DASession?
    private var isQuerying = false
    private let queryQueue = DispatchQueue(label: "com.disktempmonitor.query", qos: .utility)

    private let smartctlPath: String = {
        for p in ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return "/opt/homebrew/bin/smartctl"
    }()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = NSMenu()
        setupDisplay()
        setupDiskArbitration()
        updateDisplayText()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
        if let session = daSession {
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    // MARK: - Display Setup

    private func setupDisplay() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true
        statusItem?.menu = menu
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "Disk Temperatures")
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Update Display

    private func updateDisplayText() {
        statusItem?.button?.title = ""
        statusItem?.button?.imagePosition = .imageOnly
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if externalDisks.isEmpty {
            menu.addItem(NSMenuItem(title: "///No Ex Disk///", action: nil, keyEquivalent: ""))
        } else {
            let sortedDisks = diskTemps.keys.filter { externalDisks.contains($0) }.sorted()
            for disk in sortedDisks {
                let temp = diskTemps[disk] ?? "N/A"
                let model = diskModels[disk] ?? disk
                let item = NSMenuItem(title: "\(model) (\(disk)): \(temp)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DiskTempMonitor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }

    // MARK: - DiskArbitration (event-driven, no polling when no disk)

    private func setupDiskArbitration() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        daSession = session
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { disk, ctx in
            guard let ctx = ctx else { return }
            Unmanaged<DiskTempMonitor>.fromOpaque(ctx).takeUnretainedValue().onDiskAppeared(disk)
        }, ctx)

        DARegisterDiskDisappearedCallback(session, nil, { disk, ctx in
            guard let ctx = ctx else { return }
            Unmanaged<DiskTempMonitor>.fromOpaque(ctx).takeUnretainedValue().onDiskDisappeared(disk)
        }, ctx)

        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func onDiskAppeared(_ disk: DADisk) {
        guard let bsdCStr = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: bsdCStr)

        // Only track whole external disks (e.g., "disk4", not "disk4s1")
        guard bsdName.range(of: "^disk\\d+$", options: .regularExpression) != nil else { return }

        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool,
              !isInternal else { return }

        DispatchQueue.main.async {
            self.externalDisks.insert(bsdName)
            self.diskTemps[bsdName] = "--"
            self.updateDisplayText()

            self.queryQueue.async {
                let model = self.fetchDiskModel(bsdName)
                DispatchQueue.main.async {
                    self.diskModels[bsdName] = model
                    self.updateDisplayText()
                }
            }

            self.startTimerIfNeeded()
        }
    }

    private func onDiskDisappeared(_ disk: DADisk) {
        guard let bsdCStr = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: bsdCStr)

        DispatchQueue.main.async {
            guard self.externalDisks.contains(bsdName) else { return }
            self.externalDisks.remove(bsdName)
            self.diskTemps[bsdName] = "N/A"
            self.diskModes.removeValue(forKey: bsdName)
            self.updateDisplayText()

            if self.externalDisks.isEmpty {
                self.stopTimer()
            }
        }
    }

    // MARK: - Temperature Polling

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        triggerUpdate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.triggerUpdate()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func triggerUpdate() {
        guard !isQuerying else { return }
        isQuerying = true
        let disksSnapshot = externalDisks

        queryQueue.async { [weak self] in
            guard let self = self else { return }
            var temps: [String: String] = [:]
            for disk in disksSnapshot {
                // Check disk exists BEFORE querying
                guard self.isDiskPresent(disk) else {
                    temps[disk] = "N/A"
                    continue
                }

                let temp = self.queryTemperature(disk: disk)

                // Check disk still exists AFTER querying (detect drop caused by smartctl)
                if !self.isDiskPresent(disk) {
                    temps[disk] = "N/A"
                } else {
                    temps[disk] = temp
                }
            }
            DispatchQueue.main.async {
                for (disk, temp) in temps {
                    self.diskTemps[disk] = temp
                }
                self.updateDisplayText()
                self.isQuerying = false
            }
        }
    }

    // MARK: - Disk Presence Check

    private func isDiskPresent(_ disk: String) -> Bool {
        return FileManager.default.fileExists(atPath: "/dev/\(disk)")
    }

    // MARK: - smartctl

    private func queryTemperature(disk: String) -> String {
        if let mode = diskModes[disk] {
            return runSmartctl(disk: disk, mode: mode) ?? "N/A"
        }
        // Probe: try NVMe first, then SAT
        // NEVER use "-d auto" — it crashes certain USB/TB bridge chips
        for mode in ["nvme", "sat"] {
            if let temp = runSmartctl(disk: disk, mode: mode) {
                diskModes[disk] = mode
                return temp
            }
            if !isDiskPresent(disk) {
                return "N/A"
            }
        }
        return "N/A"
    }

    private func runSmartctl(disk: String, mode: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: smartctlPath)
        process.arguments = ["-d", mode, "-A", "/dev/\(disk)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return parseTemperature(output, mode: mode)
        } catch {
            return nil
        }
    }

    private func parseTemperature(_ output: String, mode: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // NVMe: "Temperature:                        52 Celsius"
            if mode == "nvme" &&
               trimmed.hasPrefix("Temperature:") &&
               !trimmed.contains("Sensor") &&
               !trimmed.contains("Warning") &&
               !trimmed.contains("Critical") {
                if let range = trimmed.range(of: "\\d+", options: .regularExpression) {
                    return String(trimmed[range]) + "°C"
                }
            }

            // SATA: "194 Temperature_Celsius     ...       42"
            if mode == "sat" && trimmed.contains("Temperature_Celsius") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let last = parts.last, Int(last) != nil {
                    return last + "°C"
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func fetchDiskModel(_ disk: String) -> String {
        // 1. Try to get volume name from `df` check
        let dfProcess = Process()
        let dfPipe = Pipe()
        dfProcess.executableURL = URL(fileURLWithPath: "/bin/df")
        dfProcess.arguments = []
        dfProcess.standardOutput = dfPipe
        dfProcess.standardError = FileHandle.nullDevice
        
        do {
            try dfProcess.run()
            dfProcess.waitUntilExit()
            let output = String(data: dfPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                if line.contains("/dev/\(disk)") && line.contains("/Volumes/") {
                    if let range = line.range(of: "/Volumes/") {
                        let volName = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !volName.isEmpty {
                            return volName
                        }
                    }
                }
            }
        } catch {}

        // 2. Fallback to existing diskutil hardware name
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", disk]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                if line.contains("Device / Media Name:") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        } catch {}
        return disk
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DiskTempMonitor()
app.delegate = delegate
app.run()