//
//  BalanceSparkline.swift
//  DormWatt
//

import SwiftUI

struct BalanceSparkline: View {
    let records: [ElectricityRecord]
    let warningThreshold: Double
    var lineColor: Color = .accentColor
    var warningColor: Color = .orange
    var showWarningLine = true

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            let warningY = warningY(in: proxy.size)

            ZStack {
                if showWarningLine, let warningY {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: warningY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: warningY))
                    }
                    .stroke(warningColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                Path { path in
                    guard let first = points.first else {
                        return
                    }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let sortedRecords = ElectricityAnalytics.sorted(records)
        guard sortedRecords.count > 1 else {
            return []
        }

        let balances = sortedRecords.map(\.balance) + [warningThreshold]
        let minBalance = max(0, (balances.min() ?? 0) - 1)
        let maxBalance = (balances.max() ?? 1) + 1
        let range = max(0.1, maxBalance - minBalance)
        let stepX = size.width / CGFloat(sortedRecords.count - 1)

        return sortedRecords.enumerated().map { index, record in
            let x = CGFloat(index) * stepX
            let normalizedY = (record.balance - minBalance) / range
            let y = size.height - CGFloat(normalizedY) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func warningY(in size: CGSize) -> CGFloat? {
        let sortedRecords = ElectricityAnalytics.sorted(records)
        guard !sortedRecords.isEmpty else {
            return nil
        }

        let balances = sortedRecords.map(\.balance) + [warningThreshold]
        let minBalance = max(0, (balances.min() ?? 0) - 1)
        let maxBalance = (balances.max() ?? 1) + 1
        let range = max(0.1, maxBalance - minBalance)
        let normalizedY = (warningThreshold - minBalance) / range
        return size.height - CGFloat(normalizedY) * size.height
    }
}
