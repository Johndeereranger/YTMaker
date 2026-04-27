//
//  HourlyDistributionChart.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/5/25.
//


import SwiftUI

struct HourlyDistributionChart: View {
    let distribution: [Int: Int]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = distribution[hour] ?? 0
                    let height = count == 0 ? 2 : CGFloat(count) / CGFloat(maxCount) * geometry.size.height
                    
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(barColor(for: hour))
                            .frame(height: height)
                        
                        if hour % 6 == 0 {
                            Text("\(hour)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private var maxCount: Int {
        distribution.values.max() ?? 1
    }
    
    private func barColor(for hour: Int) -> Color {
        switch hour {
        case 5..<11: return .orange.opacity(0.7)  // Morning
        case 17..<23: return .purple.opacity(0.7) // Evening
        default: return .gray.opacity(0.3)
        }
    }
}