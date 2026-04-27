//
//  ScrollArrowButtons.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
//

import SwiftUI

struct ScrollArrowButtons: View {
    let scrollTop: () -> Void
    let scrollBottom: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: scrollTop) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.gray)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
            .buttonStyle(PlainButtonStyle())
            

            Button(action: scrollBottom) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.gray)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
//        .frame(maxWidth: .infinity)
//        .padding(.bottom)
    }
}


