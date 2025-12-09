import AVFoundation
import SwiftUI
import Combine
import CoreImage

/// View model that handles camera capture, color detection and frame processing.
class ColorDetectorModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Final processed frame that is rendered in the UI.
    @Published var processedFrame: CGImage?
    
    /// Color at the center of the frame (used for small UI indicators if needed).
    @Published var detectedColor: Color = .clear
    
    /// Colors currently selected by the user (max 2 at a time).
    @Published var selectedColors: [TrackedColor] = []
    
    /// Capture session for the camera.
    let session = AVCaptureSession()
    
    /// Video output that provides raw frames from the camera.
    private let output = AVCaptureVideoDataOutput()
    
    /// Background queue for frame processing (keeps UI thread free).
    private let queue = DispatchQueue(label: "camera.processing.queue")
    
    /// Core Image context used to turn CIImage into CGImage efficiently.
    private let ciContext = CIContext()
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - Color selection (max 2)
    
    /// Adds or removes a color from the selection.
    /// Keeps at most 2 colors; when adding a third, the first one is replaced.
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
    
    // MARK: - Camera permission & configuration
    
    /// Checks camera authorization status and starts configuration when allowed.
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
    
    /// Configures the capture session, input (back camera) and output (video frames).
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
    
    // MARK: - Frame processing pipeline
    
    /// Called for every captured frame. Builds a color mask and composites
    /// boosted colors over a darker, slightly blurred background.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        // Build mask image where pixels match selected color ranges.
        let maskCI = buildColorMask(from: cgImage, extent: ciImage.extent)
        
        // Background: keep color but darken slightly and apply a very small blur.
        let darkened = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: -0.01,
            kCIInputSaturationKey: 0.9,
            kCIInputContrastKey: 1.0
        ])
        let blurredBackground = darkened.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 0.25
        ])
        
        // Foreground (selected colors): increase brightness and saturation.
        let boosted = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,
            kCIInputSaturationKey: 1.6,
            kCIInputContrastKey: 1.5
        ])
        
        // Composite boosted foreground over darkened background using the mask.
        let outputImage = boosted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurredBackground,
            kCIInputMaskImageKey: maskCI
        ])
        
        guard let outCG = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
            return
        }
        
        // Sample center pixel from original frame for UI indication.
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
    
    // MARK: - Color mask (HSV)
    
    /// Builds a grayscale mask image (white = keep/boost, black = background)
    /// based on whether pixels fall inside the HSV ranges of the selected colors.
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
        
        rgba.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * bytesPerRow + x * bytesPerPixel
                    
                    let r = Double(buffer[idx])   / 255.0
                    let g = Double(buffer[idx+1]) / 255.0
                    let b = Double(buffer[idx+2]) / 255.0
                    
                    if matchesSelectedColorsHSV(r: r, g: g, b: b) {
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
    
    /// Checks whether an RGB color falls into the HSV ranges of any selected color.
    private func matchesSelectedColorsHSV(r: Double, g: Double, b: Double) -> Bool {
        guard !selectedColors.isEmpty else { return false }
        
        let (h, s, v) = rgbToHSV(r: r, g: g, b: b)   // h in 0–1
        let hueDeg = h * 360.0
        
        for color in selectedColors {
            // Ignore pixels that are too grey or too dark for this color.
            if s < color.minSaturation || v < color.minValue {
                continue
            }
            
            let range = color.hueRangeDegrees
            if range.min <= range.max {
                // Straight range, e.g. 80–160
                if hueDeg >= range.min && hueDeg <= range.max {
                    return true
                }
            } else {
                // Wrap-around range (e.g. 330–30 for reds crossing 0°).
                if hueDeg >= range.min || hueDeg <= range.max {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Converts RGB values [0–1] into HSV components [0–1].
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
    
    // MARK: - Center color sampling
    
    /// Reads the color of the center pixel from the given image.
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
