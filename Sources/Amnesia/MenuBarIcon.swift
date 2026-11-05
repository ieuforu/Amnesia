import AppKit

/// The menu bar symbol: the app icon's dissolving speech bubble, simplified to
/// stay legible at this size. It's a template image, so the system colors it to
/// match the menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let bubble = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 5.5, width: 13, height: 10),
                xRadius: 3.5,
                yRadius: 3.5
            )
            bubble.move(to: NSPoint(x: 3.2, y: 6.5))
            bubble.line(to: NSPoint(x: 2.6, y: 2.2))
            bubble.line(to: NSPoint(x: 7.4, y: 6.5))
            bubble.close()

            // Only the left of the bubble stays solid.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 9.2, height: 18)).addClip()
            NSColor.black.setFill()
            bubble.fill()
            NSGraphicsContext.restoreGraphicsState()

            let particles: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
                (10.8, 14.2, 1.15), (10.8, 10.6, 1.15), (10.8, 7.0, 1.15),
                (13.4, 12.6, 0.95), (13.4, 8.8, 0.95),
                (15.8, 14.4, 0.75), (15.8, 10.4, 0.75),
            ]
            for particle in particles {
                let rect = NSRect(
                    x: particle.x - particle.radius,
                    y: particle.y - particle.radius,
                    width: particle.radius * 2,
                    height: particle.radius * 2
                )
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
