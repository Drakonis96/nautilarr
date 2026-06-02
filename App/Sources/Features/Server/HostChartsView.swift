import SwiftUI
import Charts

/// Live CPU / memory / network charts for an SSH host. Polls `/proc` every couple
/// of seconds while visible and plots a rolling window of samples.
struct HostChartsView: View {
    @ObservedObject var model: SSHViewModel

    private var latest: HostSample? { model.samples.last }

    var body: some View {
        ScrollView {
            if !model.metricsAvailable {
                ContentUnavailableLabel(
                    "Live charts unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: "This host doesn't expose Linux /proc metrics."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
            } else if model.samples.isEmpty {
                ProgressView("Sampling…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
            } else {
                VStack(spacing: 16) {
                    metricCard(title: "CPU", systemImage: "cpu", tint: Theme.teal,
                               value: percentText(latest?.cpu)) {
                        percentChart(keyPath: \.cpu, tint: Theme.teal)
                    }
                    metricCard(title: "Memory", systemImage: "memorychip", tint: .purple,
                               value: percentText(latest?.memUsed)) {
                        percentChart(keyPath: \.memUsed, tint: .purple)
                    }
                    metricCard(title: "Network", systemImage: "network", tint: .orange,
                               value: netText) {
                        networkChart()
                    }
                }
                .padding()
            }
        }
        .task { await loop() }
    }

    // MARK: Cards & charts

    private func metricCard<Content: View>(
        title: String, systemImage: String, tint: Color, value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                Text(value).font(.title3.weight(.bold)).foregroundStyle(tint)
            }
            content()
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private func percentChart(keyPath: KeyPath<HostSample, Double>, tint: Color) -> some View {
        Chart(model.samples) { sample in
            AreaMark(x: .value("t", sample.id), y: .value("%", sample[keyPath: keyPath]))
                .foregroundStyle(tint.opacity(0.15))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("t", sample.id), y: .value("%", sample[keyPath: keyPath]))
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .frame(height: 130)
    }

    private func networkChart() -> some View {
        Chart {
            ForEach(model.samples) { sample in
                LineMark(x: .value("t", sample.id), y: .value("B/s", sample.netDown), series: .value("dir", "Down"))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(model.samples) { sample in
                LineMark(x: .value("t", sample.id), y: .value("B/s", sample.netUp), series: .value("dir", "Up"))
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 130)
    }

    // MARK: Values

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var netText: String {
        guard let latest else { return "—" }
        return "↓ \(rate(latest.netDown))  ↑ \(rate(latest.netUp))"
    }

    private func rate(_ bytesPerSec: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file) + "/s"
    }

    // MARK: Polling

    private func loop() async {
        model.resetMetrics()
        while !Task.isCancelled {
            await model.sampleMetrics()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
