import UIKit

enum Theme {
    static let background = UIColor(hex: 0xEEF1F3)
    static let card = UIColor.white
    static let teal = UIColor(hex: 0x0D6E76)
    static let tealPressed = UIColor(hex: 0x0A585F)
    static let text = UIColor(hex: 0x16232E)
    static let secondary = UIColor(hex: 0x6B7C8A)
    static let hairline = UIColor(hex: 0xDFE5E9)
    static let danger = UIColor(hex: 0xB42318)
    static let selectedRow = UIColor(hex: 0xE3F0F1)
    static let disabledFill = UIColor(hex: 0xD6DEE2)
    static let disabledText = UIColor(hex: 0x93A3AC)
    static let checkboxBorder = UIColor(hex: 0xC3CDD4)
    static let warning = UIColor(hex: 0xB4762A)
    static let warningText = UIColor(hex: 0x8A5A1E)
    static let feed = UIColor(hex: 0xCBD7DD)
    static let feedCard = UIColor(hex: 0xF7FAFB)
    static let highlight = UIColor(hex: 0xFFEDA8)
    static let badge = UIColor(hex: 0xFFEDA8)
    static let dot = UIColor(hex: 0xBFCCD2)
    static let swipe = UIColor(hex: 0x33454F)
    static let scrim = UIColor(red: 22 / 255, green: 35 / 255, blue: 46 / 255, alpha: 0.38)
    static let radius: CGFloat = 12
    static let markRadius: CGFloat = 11

    static func titleFont() -> UIFont {
        UIFont.systemFont(ofSize: 20, weight: .heavy)
    }

    static func tabFont(selected: Bool) -> UIFont {
        UIFont.systemFont(ofSize: 14, weight: selected ? .bold : .regular)
    }

    static func mono(_ size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func avatarColor(for identifier: String) -> UIColor {
        let palette: [UInt32] = [0xDCEAEA, 0xEAE3D8, 0xE1E6EF, 0xEFE2E4, 0xE6EADF]
        let hash = identifier.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return UIColor(hex: palette[abs(hash) % palette.count])
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
