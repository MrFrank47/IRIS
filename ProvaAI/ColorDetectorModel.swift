import AVFoundation
import SwiftUI
import Combine      // <-- ADD THIS
import CoreImage
import simd


class ColorDetectorModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var processedFrame: CGImage?
    @Published var detectedColor: Color = .clear
    @Published var selectedColors: [TrackedColor] = []
    
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.processing.queue")
    private let ciContext = CIContext()
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - Color selection (max 2)
    
    func toggleColor(_ color: TrackedColor) {
        if let index = selectedColors.firstIndex(of: color) {
            selectedColors.remove(at: index)
            return
        }
        if selectedColors.count < 2 {
            selectedColors.append(color)
        } else {
            selectedColors[0] = color
        }
    }
    
    // MARK: - Camera
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setupCamera() }
            }
        default:
            break
        }
    }
    
    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        session.commitConfiguration()
        
        queue.async { self.session.startRunning() }
    }
    
    // MARK: - Frame processing
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        // Build color mask from CGImage (CPU, but simple)
        let maskCI = buildColorMask(from: cgImage, extent: ciImage.extent)
        
        // Background: desaturated + blurred
        let desaturated = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ])
        let blurred = desaturated.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 8.0
        ])
        
        // Foreground: boosted colors
        let boosted = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.6,
            kCIInputBrightnessKey: 0.1
        ])
        
        // Composite: boosted where mask is white, blurred elsewhere
        let outputImage = boosted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: maskCI
        ])
        
        guard let outCG = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
            return
        }
        
        let centerColor = sampleCenterColor(from: cgImage)
        
        DispatchQueue.main.async {
            self.processedFrame = outCG
            if let centerColor = centerColor {
                self.detectedColor = centerColor
            } else {
                self.detectedColor = .clear
            }
        }
    }
    
    // MARK: - Color mask
    
    private func buildColorMask(from cgImage: CGImage, extent: CGRect) -> CIImage {
        guard !selectedColors.isEmpty else {
            return CIImage(color: .black).cropped(to: extent)
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height
        
        var rgba = [UInt8](repeating: 0, count: totalBytes)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        rgba.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            
            ctx.draw(cgImage,
                     in: CGRect(x: 0,
                                y: 0,
                                width: CGFloat(width),
                                height: CGFloat(height)))
        }
        
        var maskData = [UInt8](repeating: 0, count: width * height)
        let threshold: Double = 0.45
        
        rgba.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * bytesPerRow + x * bytesPerPixel
                    
                    let r = Double(buffer[idx])   / 255.0
                    let g = Double(buffer[idx+1]) / 255.0
                    let b = Double(buffer[idx+2]) / 255.0
                    
                    if matchesSelectedColors(r: r, g: g, b: b, threshold: threshold) {
                        maskData[y * width + x] = 255
                    } else {
                        maskData[y * width + x] = 0
                    }
                }
            }
        }
        
        let provider = CGDataProvider(data: Data(maskData) as CFData)!
        let graySpace = CGColorSpaceCreateDeviceGray()
        
        guard let maskCG = CGImage(width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bitsPerPixel: 8,
                                   bytesPerRow: width,
                                   space: graySpace,
                                   bitmapInfo: CGBitmapInfo(),
                                   provider: provider,
                                   decode: nil,
                                   shouldInterpolate: false,
                                   intent: .defaultIntent)
        else {
            return CIImage(color: .black).cropped(to: extent)
        }
        
        return CIImage(cgImage: maskCG).cropped(to: extent)
    }
    
    private func matchesSelectedColors(r: Double, g: Double, b: Double, threshold: Double) -> Bool {
        let current = SIMD3<Double>(r, g, b)
        
        for color in selectedColors {
            let t = color.targetRGB
            let target = SIMD3<Double>(Double(t.r), Double(t.g), Double(t.b))
            let d = current - target
            let distance = (d.x*d.x + d.y*d.y + d.z*d.z).squareRoot()
            if distance < threshold {
                return true
            }
        }
        return false
    }
    
    // MARK: - Center color
    
    private func sampleCenterColor(from cgImage: CGImage) -> Color? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height
        
        var data = [UInt8](repeating: 0, count: totalBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        data.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            
            ctx.draw(cgImage,
                     in: CGRect(x: 0,
                                y: 0,
                                width: CGFloat(width),
                                height: CGFloat(height)))
        }
        
        let centerX = width / 2
        let centerY = height / 2
        let idx = centerY * bytesPerRow + centerX * bytesPerPixel
        
        let r = Double(data[idx])   / 255.0
        let g = Double(data[idx+1]) / 255.0
        let b = Double(data[idx+2]) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
}
