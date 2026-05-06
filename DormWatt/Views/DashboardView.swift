//
//  DashboardView.swift
//  DormWatt
//

import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var chartStyle: BalanceChartStyle = .line

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                balanceHero
                refreshStatus
                balanceChartCard
                consumptionSection
                widgetPreviewSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 1080, alignment: .center)
            .frame(maxWidth: .infinity)
        }
        .background(DormWattColors.background.ignoresSafeArea())
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock
                Spacer()
                refreshButton
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                refreshButton
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DormWatt")
                .font(.largeTitle.weight(.bold))
            Text("Electricity balance monitor")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refresh()
            }
        } label: {
            Label(viewModel.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isRefreshing)
    }

    private var balanceHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                remainingPanel
                    .frame(maxWidth: .infinity)
                statusPanel
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 12) {
                remainingPanel
                statusPanel
            }
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var remainingPanel: some View {
        MetricPanel(
            title: "Remaining",
            value: latestBalanceText,
            unit: "kWh",
            caption: latestUpdateText,
            tint: viewModel.isLowBalance ? .orange : .pink
        )
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusChip

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Selected consumption")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedRangeConsumption, format: .number.precision(.fractionLength(2)))
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("\(viewModel.selectedRange.title) · kWh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: 196, alignment: .topLeading)
        .background(DormWattColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statusChip: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isLowBalance ? "exclamationmark.triangle.fill" : "bolt.fill")
                .foregroundStyle(viewModel.isLowBalance ? .orange : .green)
            Text(viewModel.isLowBalance ? "Below warning line" : "Healthy balance")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((viewModel.isLowBalance ? Color.orange : Color.green).opacity(0.14))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if let errorMessage = viewModel.errorMessage {
            StatusBanner(
                title: "Refresh failed",
                message: errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if viewModel.isRefreshing {
            StatusBanner(
                title: viewModel.state.title,
                message: "Collecting live data from the electricity website.",
                systemImage: "arrow.clockwise",
                tint: .blue
            )
        } else if viewModel.records.isEmpty {
            StatusBanner(
                title: "No live data yet",
                message: "Save your website settings, then tap Refresh to collect the first record.",
                systemImage: "bolt.badge.clock",
                tint: .secondary
            )
        }
    }

    private var balanceChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    chartTitle
                    Spacer()
                    chartStyleButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    chartTitle
                    chartStyleButton
                }
            }

            timeRangePicker

            Chart {
                if chartStyle == .line {
                    ForEach(viewModel.chartRecords) { record in
                        LineMark(
                            x: .value("Time", record.timestamp),
                            y: .value("Balance", record.balance)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.pink)

                        AreaMark(
                            x: .value("Time", record.timestamp),
                            y: .value("Balance", record.balance)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.linearGradient(
                            colors: [Color.pink.opacity(0.22), Color.pink.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                } else {
                    ForEach(viewModel.chartRecords) { record in
                        BarMark(
                            x: .value("Collected", record.timestamp),
                            y: .value("Balance", record.balance),
                            width: .fixed(3)
                        )
                        .foregroundStyle(Color.pink.opacity(0.72))
                    }
                }

                RuleMark(y: .value("Warning", viewModel.lowBalanceThreshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(Color.orange.opacity(0.75))
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 270)
        }
        .padding(18)
        .background(DormWattColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var chartTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Balance trend")
                .font(.headline)
            Text("Warning line at \(viewModel.lowBalanceThreshold, format: .number.precision(.fractionLength(0...1))) kWh")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chartStyleButton: some View {
        Button {
            chartStyle.toggle()
        } label: {
            Label(chartStyle.toggleTitle, systemImage: chartStyle.toggleIconName)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var timeRangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ElectricityTimeRange.allCases) { range in
                    Button {
                        viewModel.selectedRange = range
                    } label: {
                        Text(range.shortTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.selectedRange == range ? .white : .primary)
                    .background(viewModel.selectedRange == range ? Color.pink : DormWattColors.subtlePanel)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var consumptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Consumption")
                .font(.title3.weight(.bold))

            ViewThatFits(in: .horizontal) {
                consumptionGrid(columnCount: 3, maxWidth: 820)
                consumptionGrid(columnCount: 2, maxWidth: 540)
                consumptionGrid(columnCount: 1, maxWidth: 260)
            }
        }
    }

    private func consumptionGrid(columnCount: Int, maxWidth: CGFloat) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: 260), spacing: 12, alignment: .top),
            count: columnCount
        )
        let minWidth = CGFloat(columnCount * 170) + CGFloat(max(0, columnCount - 1)) * 12

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ElectricityTimeRange.allCases) { range in
                ConsumptionCard(
                    range: range,
                    consumption: viewModel.consumption(for: range),
                    records: ElectricityAnalytics.records(in: range, from: viewModel.records),
                    threshold: viewModel.lowBalanceThreshold
                )
            }
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var widgetPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Widget preview")
                .font(.title3.weight(.bold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    WidgetSmallPreviewCard(
                        records: viewModel.records,
                        threshold: viewModel.lowBalanceThreshold
                    )
                    .frame(width: 170, height: 170)

                    WidgetMediumPreviewCard(
                        records: viewModel.records,
                        threshold: viewModel.lowBalanceThreshold
                    )
                    .frame(width: 360, height: 170)
                }

                VStack(alignment: .leading, spacing: 12) {
                    WidgetSmallPreviewCard(
                        records: viewModel.records,
                        threshold: viewModel.lowBalanceThreshold
                    )
                    .frame(width: 170, height: 170)

                    WidgetMediumPreviewCard(
                        records: viewModel.records,
                        threshold: viewModel.lowBalanceThreshold
                    )
                    .frame(maxWidth: 360, minHeight: 170)
                }
            }
        }
    }

    private var latestBalanceText: String {
        guard let balance = viewModel.latestRecord?.balance else {
            return "--"
        }
        return balance.formatted(.number.precision(.fractionLength(2)))
    }

    private var latestUpdateText: String {
        guard let date = viewModel.latestRecord?.timestamp else {
            return "Waiting for data"
        }
        return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var yDomain: ClosedRange<Double> {
        let values = viewModel.chartRecords.map(\.balance) + [viewModel.lowBalanceThreshold]
        let minValue = max(0, (values.min() ?? 0) - 2)
        let maxValue = (values.max() ?? 10) + 2
        return minValue...max(maxValue, minValue + 1)
    }
}

private enum BalanceChartStyle {
    case line
    case bar

    mutating func toggle() {
        self = self == .line ? .bar : .line
    }

    var toggleTitle: String {
        self == .line ? "Bars" : "Line"
    }

    var toggleIconName: String {
        self == .line ? "chart.bar.xaxis" : "chart.xyaxis.line"
    }
}

private struct StatusBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MetricPanel: View {
    let title: String
    let value: String
    let unit: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                Text(unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(22)
        .frame(minHeight: 196, alignment: .topLeading)
        .background(tint.opacity(0.16))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "bolt.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ConsumptionCard: View {
    let range: ElectricityTimeRange
    let consumption: Double
    let records: [ElectricityRecord]
    let threshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(range.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: iconName)
                    .foregroundStyle(tint)
            }

            Text(consumption, format: .number.precision(.fractionLength(2)))
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("kWh used")
                .font(.caption)
                .foregroundStyle(.secondary)

            MiniBarChart(records: records, lineColor: tint)
                .frame(height: 34)
        }
        .padding(16)
        .frame(minHeight: 142, alignment: .topLeading)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tint: Color {
        switch range {
        case .lastHour:
            return .pink
        case .last3Hours:
            return .blue
        case .last12Hours:
            return .purple
        case .lastDay:
            return .teal
        case .weekToDate:
            return .orange
        case .monthToDate:
            return .indigo
        }
    }

    private var iconName: String {
        switch range {
        case .lastHour, .last3Hours, .last12Hours:
            return "clock"
        case .lastDay:
            return "sun.max"
        case .weekToDate:
            return "calendar"
        case .monthToDate:
            return "calendar.badge.clock"
        }
    }
}

private struct WidgetSmallPreviewCard: View {
    let records: [ElectricityRecord]
    let threshold: Double

    var body: some View {
        let latest = ElectricityAnalytics.sorted(records).last
        let isLow = ElectricityAnalytics.isLowBalance(record: latest, threshold: threshold)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Small")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isLow ? "exclamationmark.triangle.fill" : "bolt.fill")
                    .foregroundStyle(isLow ? .orange : .pink)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(balanceText(latest))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("kWh")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MiniBarChart(records: ElectricityAnalytics.records(in: .lastDay, from: records), lineColor: isLow ? .orange : .pink)
                .frame(height: 40)

            Text(updateText(latest))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(DormWattColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct WidgetMediumPreviewCard: View {
    let records: [ElectricityRecord]
    let threshold: Double

    var body: some View {
        let latest = ElectricityAnalytics.sorted(records).last
        let isLow = ElectricityAnalytics.isLowBalance(record: latest, threshold: threshold)
        let consumption = ElectricityAnalytics.consumption(in: .lastDay, from: records)

        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Medium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(balanceText(latest))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("kWh")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Label(isLow ? "Below 5 kWh" : "Healthy", systemImage: isLow ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLow ? .orange : .green)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(updateText(latest))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(consumption, format: .number.precision(.fractionLength(2))) kWh used")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                MiniBarChart(records: ElectricityAnalytics.records(in: .lastDay, from: records), lineColor: .pink)
            }
        }
        .padding(16)
        .background(DormWattColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct MiniBarChart: View {
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

private func balanceText(_ record: ElectricityRecord?) -> String {
    guard let balance = record?.balance else {
        return "--"
    }
    return balance.formatted(.number.precision(.fractionLength(2)))
}

private func updateText(_ record: ElectricityRecord?) -> String {
    guard let timestamp = record?.timestamp else {
        return "No data yet"
    }
    return timestamp.formatted(date: .omitted, time: .shortened)
}

private enum DormWattColors {
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var panel: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var subtlePanel: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.18)
        #else
        Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }
}
