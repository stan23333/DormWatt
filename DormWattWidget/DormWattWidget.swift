//
//  DormWattWidget.swift
//  DormWattWidget
//

import SwiftUI
import WidgetKit
import OSLog

struct DormWattWidgetEntry: TimelineEntry {
    let date: Date
    let records: [ElectricityRecord]
    let threshold: Double
}

struct WidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DormWattWidgetEntry {
        DormWattWidgetEntry(
            date: Date(),
            records: ElectricityAnalytics.mockRecords(),
            threshold: 5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DormWattWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DormWattWidgetEntry>) -> Void) {
        let currentEntry = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: currentEntry.date) ?? currentEntry.date.addingTimeInterval(900)
        completion(Timeline(entries: [currentEntry], policy: .after(nextRefresh)))
    }

    private func entry() -> DormWattWidgetEntry {
        let records = WidgetHistoryReader.loadRecords()
        return DormWattWidgetEntry(
            date: Date(),
            records: records,
            threshold: 5
        )
    }
}

struct WidgetEntryView: View {
    let entry: DormWattWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DormWatt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isLow ? "exclamationmark.triangle.fill" : "bolt.fill")
                    .foregroundStyle(isLow ? .orange : .pink)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(balanceText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("kWh")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            WidgetBarChart(
                records: recentRecords(.lastDay),
                lineColor: isLow ? .orange : .pink
            )
            .frame(height: 36)

            Text(updateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .widgetBackground()
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(balanceText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("kWh")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Label(isLow ? "Below 5 kWh" : "Healthy", systemImage: isLow ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLow ? .orange : .green)

                Spacer()

                Text(updateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 116, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("24h trend")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(consumption24h, format: .number.precision(.fractionLength(2))) kWh used")
                        .font(.caption.weight(.semibold))
                }

                WidgetBarChart(
                    records: recentRecords(.lastDay),
                    lineColor: .pink
                )
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .widgetBackground()
    }

    private var latestRecord: ElectricityRecord? {
        ElectricityAnalytics.sorted(entry.records).last
    }

    private var balanceText: String {
        guard let balance = latestRecord?.balance else {
            return "--"
        }
        return balance.formatted(.number.precision(.fractionLength(2)))
    }

    private var updateText: String {
        guard let timestamp = latestRecord?.timestamp else {
            return "Open app to refresh"
        }
        return timestamp.formatted(date: .omitted, time: .shortened)
    }

    private var isLow: Bool {
        ElectricityAnalytics.isLowBalance(record: latestRecord, threshold: entry.threshold)
    }

    private var consumption24h: Double {
        ElectricityAnalytics.consumption(in: .lastDay, from: entry.records, now: entry.date)
    }

    private func recentRecords(_ range: ElectricityTimeRange) -> [ElectricityRecord] {
        ElectricityAnalytics.records(in: range, from: entry.records, now: entry.date)
    }
}

private struct WidgetBarChart: View {
    let records: [ElectricityRecord]
    let lineColor: Color

    var body: some View {
        GeometryReader { proxy in
            let values = sampledBalances(maxBars: max(1, Int(proxy.size.width / 5)))
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 0.1)
            let barWidth = max(2, proxy.size.width / CGFloat(max(values.count, 1)) - 2)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(lineColor.opacity(0.82))
                        .frame(
                            width: barWidth,
                            height: max(3, proxy.size.height * CGFloat((value - minValue) / range))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private func sampledBalances(maxBars: Int) -> [Double] {
        let cappedMaxBars = max(1, maxBars)
        let sortedRecords = ElectricityAnalytics.sorted(records)
        guard !sortedRecords.isEmpty else {
            return [0]
        }
        guard cappedMaxBars > 1 else {
            return [sortedRecords.last?.balance ?? 0]
        }
        guard sortedRecords.count > cappedMaxBars else {
            return sortedRecords.map(\.balance)
        }

        let stride = Double(sortedRecords.count - 1) / Double(cappedMaxBars - 1)
        return (0..<cappedMaxBars).map { index in
            let sourceIndex = Int((Double(index) * stride).rounded())
            return sortedRecords[min(sourceIndex, sortedRecords.count - 1)].balance
        }
    }
}

@main
struct DormWattWidget: Widget {
    let kind = DormWattSharedConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DormWatt")
        .description("Track your dorm electricity balance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum WidgetHistoryReader {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DormWattWidget", category: "Timeline")

    static func loadRecords() -> [ElectricityRecord] {
        let recordsKey = "electricityHistoryRecords"
        let latestKey = "latestElectricityRecord"
        let records = records(from: dataFromSharedFile(named: "electricity-history.json")
            ?? DormWattSharedConfiguration.legacySharedDefaultsData(forKey: recordsKey))
        guard let latestRecord = record(from: dataFromSharedFile(named: "latest-electricity-record.json")
            ?? DormWattSharedConfiguration.legacySharedDefaultsData(forKey: latestKey)) else {
            let sortedRecords = ElectricityAnalytics.sorted(records)
            logger.info("Loaded widget records without latest. count=\(sortedRecords.count, privacy: .public)")
            return sortedRecords
        }

        var mergedRecords = records
        mergedRecords.removeAll { $0.timestamp == latestRecord.timestamp }
        mergedRecords.append(latestRecord)
        let sortedRecords = ElectricityAnalytics.sorted(mergedRecords)
        logger.info("Loaded widget records. count=\(sortedRecords.count, privacy: .public), latestBalance=\(latestRecord.balance, privacy: .public)")
        return sortedRecords
    }

    private static func records(from data: Data?) -> [ElectricityRecord] {
        guard let data,
              let records = try? JSONDecoder().decode([ElectricityRecord].self, from: data) else {
            return []
        }
        return records
    }

    private static func record(from data: Data?) -> ElectricityRecord? {
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(ElectricityRecord.self, from: data)
    }

    private static func dataFromSharedFile(named fileName: String) -> Data? {
        guard let fileURL = DormWattSharedConfiguration.sharedDataURL(fileName: fileName) else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }
}

private extension View {
    func widgetBackground() -> some View {
        background(
            LinearGradient(
                colors: WidgetColors.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private enum WidgetColors {
    static var backgroundColors: [Color] {
        #if os(macOS)
        [Color(nsColor: .windowBackgroundColor), Color.pink.opacity(0.12)]
        #else
        [Color(uiColor: .secondarySystemBackground), Color.pink.opacity(0.12)]
        #endif
    }
}

struct DormWattWidget_Previews: PreviewProvider {
    private static let entry = DormWattWidgetEntry(
        date: Date(),
        records: [
            ElectricityRecord(balance: 18.2, rawText: "Preview", timestamp: Date())
        ],
        threshold: 5
    )

    static var previews: some View {
        Group {
            WidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Small")

            WidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Medium")
        }
    }
}
