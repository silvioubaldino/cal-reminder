import AppKit
import QuartzCore

/// Draws the Airplane pulling the Banner and slides it across the view's width.
final class AirplaneBannerView: NSView {
    private let containerLayer = CALayer()
    private let airplaneLayer = CALayer()
    private let ropeLayer = CAShapeLayer()
    private let bannerLayer = CALayer()
    private let bannerTextLayer = CATextLayer()

    /// The Banner's normal width: every Banner is this wide unless the title doesn't fit.
    private static let bannerBaseWidth: CGFloat = 300
    /// How wide the Banner may grow for a long title before it starts wrapping instead.
    private static let bannerMaxWidth: CGFloat = 600
    private static let bannerMinHeight: CGFloat = 44
    private static let airplaneSize = CGSize(width: 60, height: 60)
    private static let bannerFontSize: CGFloat = 14
    /// The title line (RF-05) renders bold, the time line renders italic — both the same
    /// size, so only the emphasis differs.
    private static let bannerTitleFont = NSFont.boldSystemFont(ofSize: bannerFontSize)
    private static let bannerTimeFont = NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: bannerFontSize),
        toHaveTrait: .italicFontMask
    )
    private static let bannerHorizontalPadding: CGFloat = 8
    /// Height of one rendered line — the baseline for the Banner's vertical padding.
    private static let singleLineHeight = bannerFontSize * 1.3
    /// Caps how tall the Banner can grow for a very long title (RF-05): beyond this, the
    /// text truncates with an ellipsis instead of pushing the Banner further down the screen.
    private static let bannerMaxLines = 3
    /// Gap between the Banner's leading edge and the Airplane's tail, spanned by the rope.
    private static let ropeLength: CGFloat = 26

    /// Nominal width of the Airplane + rope + Banner group, used by `FlightSpeed` to
    /// calibrate a screen-size-independent flight speed. A Banner widened to fit a long
    /// title makes the *actual* group wider — `animate` passes that real width along so
    /// the Airplane still travels at the same points per second.
    static let containerWidth = airplaneSize.width + ropeLength + bannerBaseWidth
    /// How long a skipped flight takes to cross the remaining distance.
    private static let skipDuration: CFTimeInterval = 1.5

    /// White unless the animator overrides it for contrast against a Calendar Color (RF-13).
    private var bannerTextColor: NSColor = .white

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

        // Title (bold) and time (italic) are set per flight as an NSAttributedString
        // (`attributedBannerText(for:)`), which carries its own font/color — but not
        // horizontal alignment: CATextLayer only reads that from its own `alignmentMode`,
        // ignoring NSParagraphStyle.alignment even on an attributed string.
        bannerTextLayer.alignmentMode = .center
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

        layoutContainer(BannerLayout(
            width: Self.bannerBaseWidth,
            height: Self.bannerMinHeight,
            textHeight: Self.singleLineHeight
        ))
    }

    /// The Banner's measured geometry for one flight: its own size plus the height of the
    /// text block inside it, so the lines can be centered vertically as a group.
    private struct BannerLayout {
        let width: CGFloat
        let height: CGFloat
        let textHeight: CGFloat
    }

    /// Recomputes every layer's frame for the given Banner geometry, keeping the Airplane
    /// and rope centered against a Banner that may have grown to fit its text (RF-05).
    private func layoutContainer(_ banner: BannerLayout) {
        let containerSize = CGSize(
            width: Self.airplaneSize.width + Self.ropeLength + banner.width,
            height: max(Self.airplaneSize.height, banner.height)
        )
        containerLayer.bounds = CGRect(origin: .zero, size: containerSize)

        airplaneLayer.frame = CGRect(
            x: banner.width + Self.ropeLength,
            y: (containerSize.height - Self.airplaneSize.height) / 2,
            width: Self.airplaneSize.width,
            height: Self.airplaneSize.height
        )

        bannerLayer.frame = CGRect(
            x: 0,
            y: (containerSize.height - banner.height) / 2,
            width: banner.width,
            height: banner.height
        )

        // A CATextLayer draws its lines from the top of its bounds, so the whole text block
        // is centered by giving the layer exactly the text's measured height.
        bannerTextLayer.frame = CGRect(
            x: Self.bannerHorizontalPadding,
            y: (banner.height - banner.textHeight) / 2,
            width: banner.width - Self.bannerHorizontalPadding * 2,
            height: banner.textHeight
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

    /// Builds the Banner's styled text (RF-05): the title line bold, the time line
    /// italic, both centered. `BannerText.bannerText` always joins them with one `\n`.
    private func attributedBannerText(for text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let result = NSMutableAttributedString(string: text)
        result.addAttributes(
            [.paragraphStyle: paragraphStyle, .foregroundColor: bannerTextColor],
            range: NSRange(location: 0, length: result.length)
        )

        let lineBreak = text.range(of: "\n")
        let titleRange = NSRange(text.startIndex..<(lineBreak?.lowerBound ?? text.endIndex), in: text)
        result.addAttribute(.font, value: Self.bannerTitleFont, range: titleRange)

        if let lineBreak {
            let timeRange = NSRange(lineBreak.upperBound..<text.endIndex, in: text)
            result.addAttribute(.font, value: Self.bannerTimeFont, range: timeRange)
        }

        return result
    }

    /// Measures the Banner for `text`: it keeps its base width unless the widest line
    /// doesn't fit, in which case it grows on demand up to `bannerMaxWidth`. Only past
    /// that does the text wrap (and, beyond `bannerMaxLines`, truncate) — the height then
    /// grows to fit whatever lines result.
    private func bannerLayout(for text: NSAttributedString) -> BannerLayout {
        let natural = text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let width = min(
            max(Self.bannerBaseWidth, ceil(natural.width) + Self.bannerHorizontalPadding * 2),
            Self.bannerMaxWidth
        )

        let measured = text.boundingRect(
            with: CGSize(width: width - Self.bannerHorizontalPadding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let maxTextHeight = Self.singleLineHeight * CGFloat(Self.bannerMaxLines)
        let textHeight = min(ceil(measured.height), maxTextHeight)
        // Same padding a single line gets today, so the Banner keeps its familiar look.
        let verticalPadding = Self.bannerMinHeight - Self.singleLineHeight

        return BannerLayout(
            width: width,
            height: max(Self.bannerMinHeight, textHeight + verticalPadding),
            textHeight: textHeight
        )
    }

    /// Sets the Banner's background color (RF-07, banner color is configurable).
    func setBannerColor(_ color: NSColor) {
        bannerLayer.backgroundColor = color.cgColor
    }

    /// Sets the Banner text's color, so it stays readable on a Banner painted with an
    /// arbitrary Calendar Color (RF-13). Must be set before `animate(text:speed:)`, which
    /// is what builds the styled text.
    func setBannerTextColor(_ color: NSColor) {
        bannerTextColor = color
    }

    /// Slides the Airplane + Banner left-to-right across the view, updating the banner
    /// text, and returns once the animation completes (naturally, or via `skipToEnd()`).
    /// `speed` determines how fast the Airplane crosses this view, independent of the
    /// screen's width (RF-07).
    func animate(text: String, speed: FlightSpeed) async {
        let styledText = attributedBannerText(for: text)
        layoutContainer(bannerLayout(for: styledText))
        bannerTextLayer.string = styledText

        let containerWidth = containerLayer.bounds.width
        let duration = speed.flightDuration(forScreenWidth: bounds.width, containerWidth: containerWidth)
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
