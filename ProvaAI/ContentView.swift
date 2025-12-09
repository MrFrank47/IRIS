import SwiftUI

/// Root view of the app. Shows the processed camera feed and color selection bar.
struct ContentView: View {
    /// Shared model that manages camera, color processing and user selection.
    @StateObject private var model = ColorDetectorModel()
    
    var body: some View {
        ZStack {
            // Background: processed camera frame (highlighted colors + darker background).
            if let frame = model.processedFrame {
                GeometryReader { geo in
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                // Fallback while no frame is available yet.
                Color.black.ignoresSafeArea()
            }
            
            // Foreground UI layered on top of the camera.
            VStack {
                Spacer()
                
                // Bar with color selection buttons at the bottom of the screen.
                colorSelectionBar
            }
        }
    }
    
    /// Horizontal bar of buttons that lets the user choose which colors to track.
    private var colorSelectionBar: some View {
        HStack(spacing: 12) {
            ForEach(TrackedColor.allCases) { tracked in
                let isSelected = model.selectedColors.contains(tracked)
                
                Button {
                    // Toggle this color in the model (max 2 active at once).
                    model.toggleColor(tracked)
                } label: {
                    Text(tracked.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        // Filled capsule indicates selection; darker background when inactive.
                        .background(
                            Capsule()
                                .fill(isSelected ? tracked.color : Color.black.opacity(0.6))
                        )
                        .foregroundColor(.white)
                        // Stroke keeps button shape visible against bright backgrounds.
                        .overlay(
                            Capsule()
                                .stroke(tracked.color, lineWidth: isSelected ? 2 : 1)
                        )
                        // Slight scale animation to emphasize selected colors.
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(
                            .spring(response: 0.25, dampingFraction: 0.7),
                            value: isSelected
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }
}

#Preview {
    ContentView()
}
