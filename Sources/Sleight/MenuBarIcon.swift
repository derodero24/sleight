import AppKit

/// The app icon's mark, drawn small enough for the menu bar.
///
/// A dot over a bar: a short press and a long one, which is the whole of what
/// this app does. No SF Symbol says that, and the ones that come close say
/// something else - `hand.tap` reads as a trackpad gesture, `keyboard` as an
/// input source menu. Drawing it keeps the menu bar and the Dock showing the
/// same mark, which is also the only way anyone finds it among thirty other
/// small grey glyphs.
///
/// Proportions are measured from `Icon/source.png` so the two cannot drift.
enum MenuBarIcon {
    /// Fractions of the mark's own bounding box, not of the icon canvas.
    private enum Proportion {
        static let dotDiameterInWidth: CGFloat = 0.2385
        static let dotCentreFromTop: CGFloat = 0.2085
        static let barHeight: CGFloat = 0.4013
        static let barTop: CGFloat = 0.5987
        /// Mark height as a fraction of its width.
        static let aspect: CGFloat = 0.5702
    }

    /// Chosen by eye against wifi, battery and search in a menu bar: the mark is
    /// wide and short, so matching their height would make it enormous, and
    /// matching their width leaves it looking faint. 20 balances the two.
    private static let width: CGFloat = 20

    static let mark: NSImage = {
        let size = NSSize(width: width, height: (width * Proportion.aspect).rounded())
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()

            let dot = rect.width * Proportion.dotDiameterInWidth
            // Flipped is false, so y counts up from the bottom.
            let dotCentreY = rect.height * (1 - Proportion.dotCentreFromTop)
            NSBezierPath(ovalIn: CGRect(
                x: rect.midX - dot / 2,
                y: dotCentreY - dot / 2,
                width: dot,
                height: dot)).fill()

            let barHeight = rect.height * Proportion.barHeight
            let bar = CGRect(
                x: 0,
                y: rect.height * (1 - Proportion.barTop) - barHeight,
                width: rect.width,
                height: barHeight)
            // Fully rounded ends, as in the app icon.
            NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            return true
        }
        // Template images are drawn by the system in whatever colour the menu bar
        // needs, so only the alpha above matters.
        image.isTemplate = true
        return image
    }()
}
