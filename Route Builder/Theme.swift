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
    static let radius: CGFloat = 12
    static let markRadius: CGFloat = 11

    static func titleFont() -> UIFont {
        UIFont.systemFont(ofSize: 20, weight: .heavy)
    }

    static func tabFont(selected: Bool) -> UIFont {
        UIFont.systemFont(ofSize: 14, weight: selected ? .bold : .regular)
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
