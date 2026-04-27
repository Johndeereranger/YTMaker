//
//  BloodTrackingCameraView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 7/30/25.
//


import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

struct BloodTrackingCameraView: View {
    var body: some View {
        CameraViewControllerWrapper()
            .edgesIgnoringSafeArea(.all)
    }
}


import SwiftUI
import AVFoundation

struct CameraViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}
