import AppKit
import QuartzCore

/// Draws the Airplane pulling the Banner and slides it across the view's width.
final class AirplaneBannerView: NSView {
    private let containerLayer = CALayer()
    private let airplaneLayer = CALayer()
    private let ropeLayer = CAShapeLayer()
    private let bannerLayer = CALayer()
    private let bannerTextLayer = CATextLayer()

    private static let bannerWidth: CGFloat = 300
    private static let bannerMinHeight: CGFloat = 44
    private static let airplaneSize = CGSize(width: 60, height: 60)
    private static let bannerFontSize: CGFloat = 14
    private static let bannerFont = NSFont.systemFont(ofSize: bannerFontSize)
    private static let bannerHorizontalPadding: CGFloat = 8
    /// A CATextLayer draws its (single) line from the top of its bounds, so this is also
    /// used to center a single line vertically within the taller Banner.
    private static let singleLineHeight = bannerFontSize * 1.3
    /// Caps how tall the Banner can grow for a very long title (RF-05): beyond this, the
    /// text truncates with an ellipsis instead of pushing the Banner further down the screen.
    private static let bannerMaxLines = 3
    /// Gap between the Banner's leading edge and the Airplane's tail, spanned by the rope.
    private static let ropeLength: CGFloat = 26

    /// Total width of the Airplane + rope + Banner group, used by `FlightSpeed` to
    /// compute a screen-size-independent flight duration. The Banner's width is fixed —
    /// only its height grows to fit wrapped text — so this stays constant.
    static let containerWidth = airplaneSize.width + ropeLength + bannerWidth
    /// How long a skipped flight takes to cross the remaining distance.
    private static let skipDuration: CFTimeInterval = 1.5

    private var flightContinuation: CheckedContinuation<Void, Never>?
    private var flightEndX: CGFloat = 0
    private var flightY: CGFloat = 0

    /// Called on a click anywhere on the Overlay while a flight is in progress, so the
    /// animator can accept mouse events only during the flight (RF-xx: skip a Reminder).
    var onSkipRequested: (() -> Void)?

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

        containerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Flight moves left-to-right, so the Airplane leads (trailing edge = right)
        // and the Banner trails behind it, pulled from the left via the rope.
        if let image = NSImage(named: "airplane") {
            airplaneLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        airplaneLayer.contentsScale = scale

        bannerLayer.backgroundColor = NSColor.systemPink.cgColor
        bannerLayer.cornerRadius = 8

        bannerTextLayer.font = Self.bannerFont
        bannerTextLayer.fontSize = Self.bannerFontSize
        bannerTextLayer.alignmentMode = .center
        bannerTextLayer.foregroundColor = NSColor.white.cgColor
        // Wrap long titles instead of overflowing the Banner's fixed width (RF-05); a
        // capped max height (`layoutContainer`) still needs a truncation mode for titles
        // beyond `bannerMaxLines`.
        bannerTextLayer.isWrapped = true
        bannerTextLayer.truncationMode = .end
        bannerTextLayer.contentsScale = scale
        bannerLayer.addSublayer(bannerTextLayer)

        // Rope: a slightly sagging line tying the Banner's leading edge to the
        // Airplane's tail, so the two read as one towed unit without needing artwork.
        ropeLayer.strokeColor = NSColor.textColor.withAlphaComponent(0.6).cgColor
        ropeLayer.fillColor = nil
        ropeLayer.lineWidth = 1.5
        ropeLayer.lineCap = .round
        ropeLayer.contentsScale = scale

        containerLayer.addSublayer(bannerLayer)
        containerLayer.addSublayer(ropeLayer)
        containerLayer.addSublayer(airplaneLayer)
        layer?.addSublayer(containerLayer)

        layoutContainer(bannerHeight: Self.bannerMinHeight)
    }

    /// Recomputes every layer's frame for the given Banner height, keeping the Airplane
    /// and rope centered against a Banner that may have grown to fit wrapped text (RF-05).
    private func layoutContainer(bannerHeight: CGFloat) {
        let containerSize = CGSize(
            width: Self.containerWidth,
            height: max(Self.airplaneSize.height, bannerHeight)
        )
        containerLayer.bounds = CGRect(origin: .zero, size: containerSize)

        airplaneLayer.frame = CGRect(
            x: Self.bannerWidth + Self.ropeLength,
            y: (containerSize.height - Self.airplaneSize.height) / 2,
            width: Self.airplaneSize.width,
            height: Self.airplaneSize.height
        )

        bannerLayer.frame = CGRect(
            x: 0,
            y: (containerSize.height - bannerHeight) / 2,
            width: Self.bannerWidth,
            height: bannerHeight
        )

        let textHeight = min(bannerHeight, Self.singleLineHeight * CGFloat(Self.bannerMaxLines))
        bannerTextLayer.frame = CGRect(
            x: Self.bannerHorizontalPadding,
            y: (bannerHeight - textHeight) / 2,
            width: Self.bannerWidth - Self.bannerHorizontalPadding * 2,
            height: textHeight
        )

        let ropeY = containerSize.height / 2
        let ropeStart = CGPoint(x: bannerLayer.frame.maxX, y: ropeY)
        let ropeEnd = CGPoint(x: airplaneLayer.frame.minX, y: ropeY)
        let ropePath = CGMutablePath()
        ropePath.move(to: ropeStart)
        ropePath.addQuadCurve(
            to: ropeEnd,
            control: CGPoint(x: (ropeStart.x + ropeEnd.x) / 2, y: ropeY - 6)
        )
        ropeLayer.path = ropePath
    }

    /// Measures how tall the Banner needs to be for `text` to wrap within its fixed width,
    /// capped at `bannerMaxLines` (beyond that, `truncationMode` takes over).
    private func bannerHeight(forWrapping text: String) -> CGFloat {
        let maxTextWidth = Self.bannerWidth - Self.bannerHorizontalPadding * 2
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: Self.bannerFont]
        )
        let maxTextHeight = Self.singleLineHeight * CGFloat(Self.bannerMaxLines)
        let textHeight = min(ceil(measured.height), maxTextHeight)
        // Same padding a single-line title gets today, so the common case keeps its size.
        let verticalPadding = Self.bannerMinHeight - Self.singleLineHeight
        return max(Self.bannerMinHeight, textHeight + verticalPadding)
    }

    /// Sets the Banner's background color (RF-07, banner color is configurable).
    func setBannerColor(_ color: NSColor) {
        bannerLayer.backgroundColor = color.cgColor
    }

    /// Slides the Airplane + Banner left-to-right across the view, updating the banner
    /// text, and returns once the animation completes (naturally, or via `skipToEnd()`).
    /// `speed` determines how fast the Airplane crosses this view, independent of the
    /// screen's width (RF-07).
    func animate(text: String, speed: FlightSpeed) async {
        layoutContainer(bannerHeight: bannerHeight(forWrapping: text))
        bannerTextLayer.string = text
        let duration = speed.flightDuration(forScreenWidth: bounds.width)

        let containerWidth = containerLayer.bounds.width
        let startX = -containerWidth / 2
        let endX = bounds.width + containerWidth / 2
        // Flies through the screen's top third rather than dead center.
        let y = bounds.height * 2 / 3
        flightEndX = endX
        flightY = y

        containerLayer.position = CGPoint(x: startX, y: y)

        await withCheckedContinuation { continuation in
            flightContinuation = continuation
            fly(from: startX, to: endX, y: y, duration: duration)
        }
    }

    /// Cuts the current flight short: the Airplane jumps to its present position and
    /// covers the remaining distance in `skipDuration` (RF-09, click to skip).
    /// No-op if no flight is in progress.
    func skipToEnd() {
        guard containerLayer.animation(forKey: "fly") != nil else { return }
        let currentX = containerLayer.presentation()?.position.x ?? containerLayer.position.x
        containerLayer.removeAnimation(forKey: "fly")
        containerLayer.position = CGPoint(x: currentX, y: flightY)
        fly(from: currentX, to: flightEndX, y: flightY, duration: Self.skipDuration)
    }

    override func mouseDown(with event: NSEvent) {
        onSkipRequested?()
    }

    private func fly(from startX: CGFloat, to endX: CGFloat, y: CGFloat, duration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.finishFlight()
        }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = startX
        animation.toValue = endX
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)

        containerLayer.position = CGPoint(x: endX, y: y)
        containerLayer.add(animation, forKey: "fly")

        CATransaction.commit()
    }

    private func finishFlight() {
        guard let continuation = flightContinuation else { return }
        flightContinuation = nil
        continuation.resume()
    }
}
