import SwiftUI

enum TrackedColor: String, CaseIterable, Identifiable {
    case red
    case green
    case blue
    case yellow
    
    var id: String { rawValue }
    
    var displayName: String {
        rawValue.capitalized
    }
    
    // Target RGB 0–1
    var targetRGB: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .red:    return (1.0, 0.0, 0.0)
        case .green:  return (0.0, 1.0, 0.0)
        case .blue:   return (0.0, 0.0, 1.0)
        case .yellow: return (1.0, 1.0, 0.0)
        }
    }
    
    var color: Color {
        switch self {
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
