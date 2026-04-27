//
//  StepHeaderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/3/25.
//
import SwiftUI

struct StepHeaderView: View {
    let index: Int
    let title: String

    var body: some View {
        HStack{
            Spacer()
            Text("Step \(index + 1): \(title)")
                .font(.headline)
                .padding(.bottom, 4)
                .padding(.top, 12)
            Spacer()
        }
    }
}
