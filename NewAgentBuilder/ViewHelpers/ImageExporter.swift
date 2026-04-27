//
//  ImageExporter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/6/25.
//
import Foundation
import SwiftUI


struct ImageExporter {
    static func saveToDownloads(_ image: UIImage, filename: String = "ExportedImage.png") {
        guard let data = image.pngData() else {
            print("❌ Failed to convert image to PNG")
            return
        }

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            print("✅ Saved image to: \(fileURL)")
        } catch {
            print("❌ Error saving image: \(error)")
        }
    }
    
    static func makeWhiteTransparent(_ image: UIImage) -> UIImage {
        guard let inputCGImage = image.cgImage else { return image }

        let width = inputCGImage.width
        let height = inputCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.draw(inputCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let buffer = context.data else { return image }
        let pixelBuffer = buffer.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = pixelBuffer[offset]
                let g = pixelBuffer[offset + 1]
                let b = pixelBuffer[offset + 2]

                // Change this threshold if needed (255 = pure white)
                if r > 240 && g > 240 && b > 240 {
                    pixelBuffer[offset + 3] = 0 // Set alpha to 0 (transparent)
                }
            }
        }

        guard let outputCGImage = context.makeImage() else { return image }

        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
