import SwiftUI
import NautilarrCore
import SSHKit

@MainActor
final class SSHViewModel: ObservableObject {
    @Published var statsOutput = ""
    @Published var consoleOutput = ""
    @Published var command = ""
    @Published var entries: [SSHFileEntry] = []
    @Published var currentPath = "/"
    @Published var viewingFile: String?
    @Published var fileContent = ""
    @Published var dockerContainers: [DockerContainer] = []
    @Published var dockerAvailable = true
    @Published var isWorking = false
    @Published var errorMessage: String?
    /// Set when connecting to a server whose host key isn't pinned yet — the UI
    /// shows the fingerprint and asks the user to verify before trusting.
    @Published var pendingHostKey: PendingHostKey?

    struct PendingHostKey: Identifiable {
        let id = UUID()
        let fingerprint: String
        let key: Data
    }

    /// Routes errors: a first-contact host key opens the verify prompt; anything
    /// else becomes a toast.
    private func report(_ error: Error) {
        if case let SSHSession.SSHError.hostKeyUnverified(fingerprint, key) = error {
            pendingHostKey = PendingHostKey(fingerprint: fingerprint, key: key)
        } else {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // Live host metrics (CPU / memory / network), sampled from Linux /proc.
    @Published var samples: [HostSample] = []
    @Published var metricsAvailable = true
    private var mIndex = 0
    private var prevIdle: Double?
    private var prevTotal: Double?
    private var prevRx: Double?
    private var prevTx: Double?
    private var prevAt: Date?

    private var session: SSHSession?

    func configure(session: SSHSession) { if self.session == nil { self.session = session } }

    // MARK: Docker (over SSH)

    func loadDocker() async {
        guard let session else { return }
        isWorking = true
        defer { isWorking = false }
        // Tab-separated name/status; `Up …` means running. Compatible with old
        // Docker (avoids the newer `.State` format field). Sentinel detects a
        // host without docker.
        let command = "docker ps -a --format '{{.Names}}\\t{{.Status}}' 2>/dev/null || echo __NODOCKER__"
        do {
            let output = try await session.run(command)
            if output.contains("__NODOCKER__") {
                dockerAvailable = false; dockerContainers = []; return
            }
            dockerAvailable = true
            dockerContainers = output.split(separator: "\n").compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard let name = parts.first, !name.isEmpty else { return nil }
                return DockerContainer(name: name, status: parts.count > 1 ? parts[1] : "")
            }
        } catch {
            report(error)
        }
    }

    func dockerAction(_ action: String, container: String) async {
        guard let session else { return }
        isWorking = true
        defer { isWorking = false }
        _ = try? await session.run("docker \(action) \(container)")
        await loadDocker()
    }

    /// Common host-stats one-liners (best-effort; missing tools just print nothing).
    func loadStats() async {
        guard let session else { return }
        isWorking = true
        defer { isWorking = false }
        let command = """
        echo '== Uptime =='; uptime;
        echo; echo '== Memory =='; free -h 2>/dev/null || vm_stat;
        echo; echo '== Disk =='; df -h 2>/dev/null | head -n 12;
        echo; echo '== Docker =='; docker ps --format 'table {{.Names}}\\t{{.Status}}' 2>/dev/null || echo 'docker not available'
        """
        do { statsOutput = try await session.run(command) }
        catch { report(error) }
    }

    // MARK: Live metrics

    func resetMetrics() {
        samples = []; mIndex = 0
        prevIdle = nil; prevTotal = nil; prevRx = nil; prevTx = nil; prevAt = nil
        metricsAvailable = true
    }

    /// Samples CPU%, memory% and network throughput from `/proc` over SSH. CPU
    /// and network are computed as deltas between samples; memory is instantaneous.
    func sampleMetrics() async {
        guard let session else { return }
        let cmd = "echo '#CPU'; head -n1 /proc/stat 2>/dev/null; echo '#MEM'; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo 2>/dev/null; echo '#NET'; cat /proc/net/dev 2>/dev/null"
        guard let output = try? await session.run(cmd) else { return }
        parseMetrics(output)
    }

    private func parseMetrics(_ output: String) {
        var cpuLine = "", memLines: [String] = [], netLines: [String] = []
        var section = ""
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("#CPU") { section = "cpu"; continue }
            if line.hasPrefix("#MEM") { section = "mem"; continue }
            if line.hasPrefix("#NET") { section = "net"; continue }
            switch section {
            case "cpu": if cpuLine.isEmpty { cpuLine = line }
            case "mem": memLines.append(line)
            case "net": netLines.append(line)
            default: break
            }
        }

        let cpuNums = cpuLine.split(separator: " ").compactMap { Double($0) }
        guard cpuLine.hasPrefix("cpu"), cpuNums.count >= 4 else { metricsAvailable = false; return }
        let total = cpuNums.reduce(0, +)
        let idle = cpuNums[3] + (cpuNums.count > 4 ? cpuNums[4] : 0)
        var cpuPct = 0.0
        if let pt = prevTotal, let pi = prevIdle, total - pt > 0 {
            cpuPct = max(0, min(100, (1 - (idle - pi) / (total - pt)) * 100))
        }
        prevTotal = total; prevIdle = idle

        var memTotal = 0.0, memAvail = 0.0
        for l in memLines {
            let v = l.split(separator: " ").compactMap { Double($0) }.first ?? 0
            if l.contains("MemTotal") { memTotal = v }
            if l.contains("MemAvailable") { memAvail = v }
        }
        let memPct = memTotal > 0 ? max(0, min(100, (memTotal - memAvail) / memTotal * 100)) : 0

        var rx = 0.0, tx = 0.0
        for l in netLines where l.contains(":") {
            let comps = l.split(separator: ":", maxSplits: 1)
            guard comps.count == 2 else { continue }
            let iface = comps[0].trimmingCharacters(in: .whitespaces)
            if iface == "lo" || iface.isEmpty { continue }
            let nums = comps[1].split(separator: " ").compactMap { Double($0) }
            if nums.count >= 9 { rx += nums[0]; tx += nums[8] }
        }
        let now = Date()
        var down = 0.0, up = 0.0
        if let prx = prevRx, let ptx = prevTx, let pat = prevAt {
            let dt = now.timeIntervalSince(pat)
            if dt > 0 { down = max(0, (rx - prx) / dt); up = max(0, (tx - ptx) / dt) }
        }
        prevRx = rx; prevTx = tx; prevAt = now

        metricsAvailable = true
        samples.append(HostSample(id: mIndex, cpu: cpuPct, memUsed: memPct, netDown: down, netUp: up))
        mIndex += 1
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
    }

    func runCommand() async {
        guard let session, !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let cmd = command
        command = ""
        consoleOutput += "$ \(cmd)\n"
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await session.run(cmd)
            consoleOutput += result + (result.hasSuffix("\n") ? "" : "\n")
        } catch {
            consoleOutput += "error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)\n"
        }
    }

    func list(_ path: String) async {
        guard let session else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            entries = try await session.list(path)
            currentPath = path
        } catch {
            report(error)
        }
    }

    func open(_ entry: SSHFileEntry) async {
        if entry.isDirectory {
            await list(entry.path)
        } else {
            guard let session else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                fileContent = try await session.readTextFile(entry.path)
                viewingFile = entry.name
            } catch {
                report(error)
            }
        }
    }

    func goUp() async {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await list(parent.isEmpty ? "/" : parent)
    }

    func disconnect() async { await session?.disconnect() }
}

/// One live host-metrics sample (percentages 0–100; network in bytes/sec).
struct HostSample: Identifiable, Equatable {
    let id: Int
    let cpu: Double
    let memUsed: Double
    let netDown: Double
    let netUp: Double
}

/// A Docker container parsed from `docker ps -a` over SSH.
struct DockerContainer: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let status: String
    var isRunning: Bool { status.hasPrefix("Up") }
}

/// SSH tools for a server instance: host stats, Docker, an interactive console,
/// and an SFTP file browser. Optionally gated behind Face ID.
struct SSHDetailView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = SSHViewModel()

    enum Tab: String, CaseIterable { case charts = "Charts", stats = "Stats", docker = "Docker", console = "Console", files = "Files" }
    @State private var tab: Tab = .charts
    @State private var unlocked = false

    var body: some View {
        Group {
            if settings.faceIDForSSH && !unlocked {
                lockScreen
            } else {
                content
            }
        }
        .navigationTitle(instance.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        instanceStore.resetSSHHostKey(for: instance)
                        model.errorMessage = "Trusted host key forgotten. It will be re-pinned on the next connection."
                    } label: {
                        Label("Reset trusted host key", systemImage: "key.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if let session = instanceStore.sshSession(for: instance, timeout: TimeInterval(settings.sshTimeout)) {
                model.configure(session: session)
            }
            if settings.faceIDForSSH && !unlocked {
                unlocked = await BiometricGate.authenticate(reason: "Unlock SSH access")
            }
            if unlocked || !settings.faceIDForSSH {
                await model.loadStats()
                await model.loadDocker()
                await model.list("/")
            }
        }
        .onDisappear { Task { await model.disconnect() } }
        .alert("Verify SSH host", isPresented: Binding(
            get: { model.pendingHostKey != nil },
            set: { if !$0 { model.pendingHostKey = nil } }
        )) {
            Button("Trust this host") { trustPendingHostKey() }
            Button("Cancel", role: .cancel) { model.pendingHostKey = nil }
        } message: {
            Text("First connection to this server. Make sure this fingerprint matches your server's SSH host key before trusting it:\n\n\(model.pendingHostKey?.fingerprint ?? "")\n\nIf it doesn't match, someone may be intercepting the connection — do not trust it.")
        }
    }

    /// Pins the verified host key, then reconnects with the now-trusted key.
    private func trustPendingHostKey() {
        guard let pending = model.pendingHostKey else { return }
        instanceStore.trustSSHHostKey(pending.key, for: instance)
        model.pendingHostKey = nil
        Task {
            await model.loadStats()
            await model.loadDocker()
            await model.list("/")
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid").font(.system(size: 48)).foregroundStyle(Theme.teal)
            Text("SSH is protected").font(.headline)
            Button("Unlock") {
                Task {
                    unlocked = await BiometricGate.authenticate(reason: "Unlock SSH access")
                    if unlocked { await model.loadStats(); await model.loadDocker(); await model.list("/") }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .charts: HostChartsView(model: model)
            case .stats: statsView
            case .docker: dockerView
            case .console: consoleView
            case .files: filesView
            }
        }
        .overlay(alignment: .bottom) { Toast(message: model.errorMessage) { model.errorMessage = nil } }
    }

    private var dockerView: some View {
        List {
            if !model.dockerAvailable {
                Text("Docker is not available on this host.").foregroundStyle(.secondary)
            } else if model.dockerContainers.isEmpty {
                Text("No containers.").foregroundStyle(.secondary)
            } else {
                ForEach(model.dockerContainers) { container in
                    HStack(spacing: 10) {
                        Circle().fill(container.isRunning ? .green : .secondary).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(container.name).font(.subheadline).lineLimit(1)
                            Text(container.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            if container.isRunning {
                                Button { Task { await model.dockerAction("restart", container: container.name) } } label: {
                                    Label("Restart", systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) { Task { await model.dockerAction("stop", container: container.name) } } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                            } else {
                                Button { Task { await model.dockerAction("start", container: container.name) } } label: {
                                    Label("Start", systemImage: "play.fill")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .refreshable { await model.loadDocker() }
    }

    private var statsView: some View {
        ScrollView {
            Text(model.statsOutput.isEmpty ? "Loading…" : model.statsOutput)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .refreshable { await model.loadStats() }
    }

    private var consoleView: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(model.consoleOutput)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            HStack {
                TextField("command", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { Task { await model.runCommand() } }
                Button { Task { await model.runCommand() } } label: { Image(systemName: "arrow.up.circle.fill") }
                    .disabled(model.isWorking)
            }
            .padding()
        }
    }

    private var filesView: some View {
        List {
            HStack {
                Image(systemName: "folder")
                Text(model.currentPath).font(.footnote.monospaced()).lineLimit(1)
                Spacer()
                if model.currentPath != "/" {
                    Button("Up") { Task { await model.goUp() } }.font(.caption)
                }
            }
            ForEach(model.entries) { entry in
                Button { Task { await model.open(entry) } } label: {
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Theme.teal : .secondary)
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        if let size = entry.size, !entry.isDirectory {
                            Text(Format.bytes(size)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: Binding(get: { model.viewingFile != nil }, set: { if !$0 { model.viewingFile = nil } })) {
            NavigationStack {
                ScrollView {
                    Text(model.fileContent)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(model.viewingFile ?? "File")
                .navigationBarTitleDisplayModeInlineCompat()
                .doneToolbar { model.viewingFile = nil }
            }
        }
    }
}

private extension View {
    func navigationBarTitleDisplayModeInlineCompat() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}
