//
//  WeatherDataViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/6/25.
//


import SwiftUI

struct WeatherDataViewer: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var showStoredData = false

    var body: some View {
        VStack(spacing: 20) {
            Button("Fetch Weather Data") {
                viewModel.fetchHistoricalWeather()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            if viewModel.isLoading {
                ProgressView("Loading Weather...")
            }

            Button("Show Stored High/Low Data") {
                showStoredData.toggle()
            }

            if showStoredData {
                List {
                    ForEach(getSortedStoredDates(), id: \.self) { date in
                        if let hl = HighLowManager.shared.getHighLow(for: date) {
                            HStack {
                                Text(date, style: .date)
                                Spacer()
                                Text("High: \(hl.high)°  Low: \(hl.low)°")
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func getSortedStoredDates() -> [Date] {
        return HighLowManager.shared
            .getAll()
            .keys
            .sorted()
    }
}