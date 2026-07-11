import AppKit
import QuartzCore

/// Draws the Airplane pulling the Banner and slides it across the view's width.
final class AirplaneBannerView: NSView {
    private let containerLayer = CALayer()
    private let airplaneLayer = CALayer()
    private let bannerLayer = CALayer()
    private let bannerTextLayer = CATextLayer()

    private static let flightDuration: CFTimeInterval = 6.0
    private static let bannerSize = CGSize(width: 420, height: 60)
    private static let airplaneSize = CGSize(width: 60, height: 60)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setUpLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setUpLayers()
    }

    private func setUpLayers() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let containerSize = CGSize(
            width: Self.airplaneSize.width + Self.bannerSize.width,
            height: max(Self.airplaneSize.height, Self.bannerSize.height)
        )
        containerLayer.bounds = CGRect(origin: .zero, size: containerSize)
        containerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Flight moves left-to-right, so the Airplane leads (trailing edge = right)
        // and the Banner trails behind it, pulled from the left.
        if let image = NSImage(named: "airplane") {
            airplaneLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        airplaneLayer.frame = CGRect(
            x: Self.bannerSize.width,
            y: (containerSize.height - Self.airplaneSize.height) / 2,
            width: Self.airplaneSize.width,
            height: Self.airplaneSize.height
        )
        airplaneLayer.contentsScale = scale

        bannerLayer.backgroundColor = NSColor.systemPink.cgColor
        bannerLayer.cornerRadius = 8
        bannerLayer.frame = CGRect(
            x: 0,
            y: (containerSize.height - Self.bannerSize.height) / 2,
            width: Self.bannerSize.width,
            height: Self.bannerSize.height
        )

        bannerTextLayer.fontSize = 18
        bannerTextLayer.alignmentMode = .center
        bannerTextLayer.foregroundColor = NSColor.white.cgColor
        bannerTextLayer.frame = bannerLayer.bounds.insetBy(dx: 8, dy: 0)
        bannerTextLayer.contentsScale = scale
        bannerLayer.addSublayer(bannerTextLayer)

        containerLayer.addSublayer(bannerLayer)
        containerLayer.addSublayer(airplaneLayer)
        layer?.addSublayer(containerLayer)
    }

    /// Slides the Airplane + Banner left-to-right across the view, updating the banner
    /// text, and returns once the animation completes.
    func animate(text: String) async {
        bannerTextLayer.string = text

        let containerWidth = containerLayer.bounds.width
        let startX = -containerWidth / 2
        let endX = bounds.width + containerWidth / 2
        let y = bounds.height / 2

        containerLayer.position = CGPoint(x: startX, y: y)

        await withCheckedContinuation { continuation in
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                continuation.resume()
            }

            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = startX
            animation.toValue = endX
            animation.duration = Self.flightDuration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)

            containerLayer.position = CGPoint(x: endX, y: y)
            containerLayer.add(animation, forKey: "fly")

            CATransaction.commit()
        }
    }
}
