import SwiftUI
import Charts
import SiliciumShared
import SiliciumCore
import SiliciumStorage

struct LiveChart: View {
    let points: [MetricPoint]
    let color: Color
    var yDomain: ClosedRange<Double>?
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    var windowSeconds: TimeInterval = 60

    var body: some View {
        let end = points.last?.date ?? .now
        Chart(points) { p in
            AreaMark(x: .value("Temps", p.date), y: .value("Valeur", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Temps", p.date), y: .value("Valeur", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXScale(domain: end.addingTimeInterval(-windowSeconds)...end)
        .chartYScale(domain: yDomain ?? autoDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)).font(.caption2).foregroundStyle(.secondary) } }
            }
        }
        .frame(height: 96)
    }

    private var autoDomain: ClosedRange<Double> {
        let hi = max(points.map(\.value).max() ?? 1, 0.0001)
        return 0...(hi * 1.15)
    }
}

struct HistoryChart: View {
    let repo: HistoryRepository?
    let metric: String
    let range: HistoryRange
    let color: Color
    var yDomain: ClosedRange<Double>?
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    @State private var points: [HistoryPoint] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if points.isEmpty {
                ContentUnavailableView(loaded ? "Pas encore de données" : "Chargement…", systemImage: "chart.xyaxis.line",
                                       description: Text(loaded ? "L'historique se remplit au fil de l'utilisation." : ""))
                    .frame(height: 110)
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("Temps", p.date), yStart: .value("Min", 0), yEnd: .value("Valeur", p.average))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Temps", p.date), y: .value("Moyenne", p.average))
                        .interpolationMethod(.monotone).foregroundStyle(color)
                    PointMark(x: .value("Temps", p.date), y: .value("Pic", p.maximum))
                        .symbolSize(6).foregroundStyle(color.opacity(0.4))
                }
                .chartYScale(domain: yDomain ?? 0...max(points.map(\.maximum).max() ?? 1, 0.0001) * 1.15)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)).font(.caption2).foregroundStyle(.secondary) } }
                    }
                }
                .frame(height: 110)
            }
        }
        .task(id: "\(metric)-\(range.rawValue)") { await reload() }
        .task(id: "\(metric)-\(range.rawValue)-refresh") {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); await reload() }
        }
    }

    private func reload() async {
        guard let repo else { loaded = true; return }
        points = (try? await repo.series(metric: metric, range: range)) ?? []
        loaded = true
    }
}
