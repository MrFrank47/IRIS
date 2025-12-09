import SwiftUI

/// Represents a color the user can choose to detect.
/// Each case includes metadata for UI display and HSV detection.
enum TrackedColor: String, CaseIterable, Identifiable {
    
    case red
    case green
    case blue
    case yellow
    
    /// Required by `Identifiable` for use in SwiftUI lists.
    var id: String { rawValue }
    
    /// Human-readable name shown on the buttons.
    var displayName: String {
        rawValue.capitalized
    }
    
    /// SwiftUI color used for UI tinting (button backgrounds, strokes, etc.)
    var color: Color {
        switch self {
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
    
    // MARK: - HSV Detection Settings
    
    /// Allowed hue range in **degrees** (0–360) for each color.
    /// We use wide ranges so variations like light blue, navy, dark green, etc., are detected.
    /// Wrap-around (330–30) is handled in the matcher.
    var hueRangeDegrees: (min: Double, max: Double) {
        switch self {
        case .red:
            return (min: 330, max: 30)      // covers hues around the 0° boundary
        case .yellow:
            return (min: 40, max: 80)
        case .green:
            return (min: 80, max: 160)
        case .blue:
            return (min: 180, max: 260)     // covers cyan→deep blue→navy
        }
    }
    
    /// Minimum saturation required, to avoid picking up grey or washed-out areas.
    /// Lower values make detection more permissive.
    var minSaturation: Double {
        switch self {
        case .red:    return 0.20
        case .yellow: return 0.20
        case .green:  return 0.18
        case .blue:   return 0.18
        }
    }
    
    /// Minimum brightness (value) required.
    /// Blue and green allow darker values so navy and dark forest green are still recognized.
    var minValue: Double {
        switch self {
        case .red:    return 0.15
        case .yellow: return 0.20
        case .green:  return 0.12
        case .blue:   return 0.08
        }
    }
}
