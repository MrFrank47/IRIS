import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    // 1. Create the view
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    // 2. Update the view (not needed for layout anymore)
    func updateUIView(_ uiView: VideoPreviewView, context: Context) { }
}

// 3. The "Engine Room" - A custom UIKit view that handles its own layout
class VideoPreviewView: UIView {
    
    // This defines the backing layer type for this view
    // By doing this, we don't need to add sublayers manually!
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    // Helper to get the layer as the correct type
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
