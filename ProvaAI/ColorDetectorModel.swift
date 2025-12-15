import AVFoundation
import SwiftUI
import Combine
import CoreImage

class ColorDetectorModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var processedFrame: CGImage?
    
    // New controls
    @Published var selectedMode: VisionMode = .normal
    @Published var isGrayscaleEnabled: Bool = false
    
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.processing.queue")
    private let ciContext = CIContext()
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func selectMode(_ mode: VisionMode) {
        selectedMode = mode
    }
    
    // Map disability profile -> which colors we want to highlight
    private func activeColorRanges() -> [TrackedColor] {
        switch selectedMode {
        case .deuteranomaly:
            // Green-weak: emphasize greens (and yellow-ish greens show up via widened green range below)
            return [.green]
        case .protanomaly:
            // Red-weak: emphasize reds
            return [.red]
        case .tritanomaly:
            return [.blue, .yellow]
        case .normal:
            return []
        }
    }
    
    // MARK: - Camera permission
    
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
    
    // MARK: - Camera setup
    
    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(output) { session.addOutput(output) }
        
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
        
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = original.extent
        
        // Base background: either full-color or grayscale, depending on toggle
        let baseBackground: CIImage
        if isGrayscaleEnabled {
            baseBackground = original.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0
            ])
        } else {
            baseBackground = original
        }
        
        // If Normal mode: just show the base (color or grayscale)
        // If Normal mode: show raw camera frame (no grayscale, no blur, no darkening)
        if selectedMode == .normal {
            guard let outCG = ciContext.createCGImage(original, from: extent) else { return }
            DispatchQueue.main.async { self.processedFrame = outCG }
            return
        }
        
        // For D/P/T modes: build mask using selected ranges
        guard let cgForMask = ciContext.createCGImage(original, from: extent) else { return }
        let maskCI = buildColorMask(from: cgForMask, extent: extent)
        
        // Background: darker + tiny blur (still grayscale if toggle ON)
        let darkened = baseBackground.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: -0.10,
            kCIInputSaturationKey: isGrayscaleEnabled ? 0.0 : 0.90,
            kCIInputContrastKey: 1.0
        ])
        let blurredBackground = darkened.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 0.6
        ])
        
        // Foreground: ALWAYS from original color image so highlight still shows color in B/W mode
        let boosted = original.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.20,
            kCIInputSaturationKey: 1.70,
            kCIInputContrastKey: 1.35
        ])
        
        // Composite boosted colors over darker/blurred background using mask
        let outputImage = boosted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurredBackground,
            kCIInputMaskImageKey: maskCI
        ])
        
        guard let outCG = ciContext.createCGImage(outputImage, from: extent) else { return }
        DispatchQueue.main.async { self.processedFrame = outCG }
    }
    
    // MARK: - Mask building (HSV)
    
    private func buildColorMask(from cgImage: CGImage, extent: CGRect) -> CIImage {
        let selected = activeColorRanges()
        guard !selected.isEmpty else {
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
            
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        
        var maskData = [UInt8](repeating: 0, count: width * height)
        
        rgba.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * bytesPerRow + x * bytesPerPixel
                    
                    let r = Double(buffer[idx])   / 255.0
                    let g = Double(buffer[idx+1]) / 255.0
                    let b = Double(buffer[idx+2]) / 255.0
                    
                    if matchesHSV(r: r, g: g, b: b, against: selected) {
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
    
    private func matchesHSV(r: Double, g: Double, b: Double, against colors: [TrackedColor]) -> Bool {
        let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
        let hueDeg = h * 360.0
        
        for color in colors {
            if s < color.minSaturation || v < color.minValue { continue }
            
            let range = color.hueRangeDegrees
            if range.min <= range.max {
                if hueDeg >= range.min && hueDeg <= range.max { return true }
            } else {
                // wrap-around range (red)
                if hueDeg >= range.min || hueDeg <= range.max { return true }
            }
        }
        
        return false
    }
    
    private func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal
        
        var h: Double = 0
        if delta != 0 {
            if maxVal == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxVal == g {
                h = 60 * (((b - r) / delta) + 2)
            } else {
                h = 60 * (((r - g) / delta) + 4)
            }
        }
        if h < 0 { h += 360 }
        
        let s = maxVal == 0 ? 0 : (delta / maxVal)
        let v = maxVal
        
        return (h / 360.0, s, v)
    }
}
