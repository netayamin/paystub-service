import SwiftUI

/// Manrope variable font helpers.
/// Weights map directly to the variable font's wght axis.
enum Manrope {
    // MARK: - Named weights matching the design spec

    /// 9px Extra Bold — signal labels ("JUST OPENED")
    static func signalLabel(_ size: CGFloat = 9) -> Font {
        .custom("Manrope", size: size).weight(.heavy)
    }

    /// 10px Medium — time indicators, secondary details
    static func detail(_ size: CGFloat = 10) -> Font {
        .custom("Manrope", size: size).weight(.medium)
    }

    /// 11px Bold Uppercase — button text ("BOOK")
    static func button(_ size: CGFloat = 11) -> Font {
        .custom("Manrope", size: size).weight(.bold)
    }

    /// 14px Bold Uppercase — restaurant name, section title
    static func title(_ size: CGFloat = 14) -> Font {
        .custom("Manrope", size: size).weight(.bold)
    }

    /// 10px Bold Uppercase — status label ("ACTIVE NOW")
    static func status(_ size: CGFloat = 10) -> Font {
        .custom("Manrope", size: size).weight(.bold)
    }
}
