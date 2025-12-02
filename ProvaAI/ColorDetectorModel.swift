import AVFoundation
import SwiftUI
import Combine

class ColorDetectorModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var detectedColor: Color = .black
    @Published var rgbString: String = "R:0 G:0 B:0"
    
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue")
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setupCamera() }
            }
        default: break
        }
    }
    
    private func setupCamera() {
        session.beginConfiguration()
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        if session.canAddInput(input) { session.addInput(input) }
        
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if session.canAddOutput(output) { session.addOutput(output) }
        
        session.commitConfiguration()
        
        queue.async { self.session.startRunning() }
    }
    
    // Core logic: Process pixel buffer
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        // Calculate center pixel coordinates
        let centerX = width / 2
        let centerY = height / 2
        let offset = (centerY * bytesPerRow) + (centerX * 4) // 4 bytes per pixel (BGRA)
        
        let b = CGFloat(baseAddress!.load(fromByteOffset: offset, as: UInt8.self)) / 255.0
        let g = CGFloat(baseAddress!.load(fromByteOffset: offset + 1, as: UInt8.self)) / 255.0
        let r = CGFloat(baseAddress!.load(fromByteOffset: offset + 2, as: UInt8.self)) / 255.0
        
        DispatchQueue.main.async {
            self.detectedColor = Color(red: r, green: g, blue: b)
            self.rgbString = String(format: "R:%.0f G:%.0f B:%.0f", r*255, g*255, b*255)
        }
    }
}
