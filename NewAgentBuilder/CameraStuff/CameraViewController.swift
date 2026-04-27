//
//  CameraViewController.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 7/30/25.
//

import UIKit
import AVFoundation
import CoreImage

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let context = CIContext()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: CALayer!
    private var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        imageView = UIImageView(frame: view.bounds)
        imageView.contentMode = .scaleAspectFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        setupCamera()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        imageView.frame = view.bounds
    }

    private func setupCamera() {
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.processing"))
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Fix orientation AFTER adding output
        DispatchQueue.main.async {
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

        session.startRunning()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            self.updateVideoOrientation()
        })
    }
    
    private func updateVideoOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        
        if connection.isVideoOrientationSupported {
            switch UIDevice.current.orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                connection.videoOrientation = .portrait
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 🩸 MAKE RED SCREAM - Simple but aggressive approach
        let enhancedImage = makeRedScream(image: ciImage)

        guard let cgImage = context.createCGImage(enhancedImage, from: enhancedImage.extent) else { return }

        DispatchQueue.main.async {
            self.imageView.image = UIImage(cgImage: cgImage)
        }
    }
    
    private func makeRedScream(image: CIImage) -> CIImage {
        // Step 1: Massively boost red channel and kill everything else
        guard let redBoostFilter = CIFilter(name: "CIColorMatrix") else { return image }
        redBoostFilter.setValue(image, forKey: kCIInputImageKey)
        
        // AGGRESSIVE red boost - multiply red by 5, kill green/blue
        redBoostFilter.setValue(CIVector(x: 5.0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        redBoostFilter.setValue(CIVector(x: 0, y: 0.1, z: 0, w: 0), forKey: "inputGVector")
        redBoostFilter.setValue(CIVector(x: 0, y: 0, z: 0.1, w: 0), forKey: "inputBVector")
        redBoostFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        guard let redBoosted = redBoostFilter.outputImage else { return image }
        
        // Step 2: Max out saturation and contrast
        guard let saturationFilter = CIFilter(name: "CIColorControls") else { return redBoosted }
        saturationFilter.setValue(redBoosted, forKey: kCIInputImageKey)
        saturationFilter.setValue(3.0, forKey: kCIInputSaturationKey) // Max saturation
        saturationFilter.setValue(2.5, forKey: kCIInputContrastKey)   // High contrast
        saturationFilter.setValue(0.3, forKey: kCIInputBrightnessKey) // Slightly brighter
        
        return saturationFilter.outputImage ?? image
    }
    
    private func createRedMask(image: CIImage) -> CIImage {
        // Create mask for red range using color matrix
        guard let maskFilter = CIFilter(name: "CIColorMatrix") else { return image }
        maskFilter.setValue(image, forKey: kCIInputImageKey)
        
        // This is a simplified red detection - emphasize red, reduce green/blue
        maskFilter.setValue(CIVector(x: 1.5, y: -0.5, z: -0.5, w: 0), forKey: "inputRVector") // Emphasize red, reduce green/blue
        maskFilter.setValue(CIVector(x: -0.3, y: 0.3, z: -0.3, w: 0), forKey: "inputGVector")
        maskFilter.setValue(CIVector(x: -0.3, y: -0.3, z: 0.3, w: 0), forKey: "inputBVector")
        maskFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        guard let colorAdjusted = maskFilter.outputImage else { return image }
        
        // Convert to grayscale mask
        guard let grayscaleFilter = CIFilter(name: "CIColorMonochrome") else { return colorAdjusted }
        grayscaleFilter.setValue(colorAdjusted, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor.white, forKey: kCIInputColorKey)
        grayscaleFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        return grayscaleFilter.outputImage ?? image
    }
    
    private func createRedOverlay(for image: CIImage) -> CIImage {
        // Create a vibrant red overlay
        let redColor = CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.8)
        guard let colorFilter = CIFilter(name: "CIConstantColorGenerator") else { return image }
        colorFilter.setValue(redColor, forKey: kCIInputColorKey)
        
        guard let redImage = colorFilter.outputImage else { return image }
        
        // Crop to image size
        guard let cropFilter = CIFilter(name: "CICrop") else { return redImage }
        cropFilter.setValue(redImage, forKey: kCIInputImageKey)
        cropFilter.setValue(CIVector(cgRect: image.extent), forKey: "inputRectangle")
        
        return cropFilter.outputImage ?? image
    }
}

// MARK: - Alternative Simpler Approach
extension CameraViewController {
    
    // If the above is too complex, try this simpler approach:
    private func simpleRedEnhancement(image: CIImage) -> CIImage {
        // Method 1: Selective color adjustment
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(1.5, forKey: kCIInputSaturationKey) // Boost saturation
        filter.setValue(1.2, forKey: kCIInputContrastKey)   // Increase contrast
        
        guard let saturatedImage = filter.outputImage else { return image }
        
        // Method 2: Hue-specific boost
        guard let hueFilter = CIFilter(name: "CIHueAdjust") else { return saturatedImage }
        hueFilter.setValue(saturatedImage, forKey: kCIInputImageKey)
        hueFilter.setValue(0.1, forKey: kCIInputAngleKey) // Slight red shift
        
        return hueFilter.outputImage ?? saturatedImage
    }
}
