import SwiftUI
import AppKit

/// AppKit view that draws one slice with crosshair and orientation labels, and handles
/// click/drag (move cursor), scroll and arrow keys (change slice), option- or right-drag (window/level).
final class SliceNSView: NSView {
    var image: CGImage?
    var physicalSize: CGSize = .zero
    var pixelSize: CGSize = .zero
    var crosshair: CGPoint?
    var labels = OrientationLabels.none
    var title = ""
    var detail = ""
    var smooth = true
    /// Colour of the horizontal and vertical crosshair lines (the planes they represent).
    var horizontalLineColor = NSColor.systemTeal
    var verticalLineColor = NSColor.systemTeal
    var backgroundColor = NSColor.black

    var onSelect: ((Int, Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onWindowDrag: ((CGFloat, CGFloat) -> Void)?
    var onHover: (((Int, Int)?) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var scrollAccumulator: CGFloat = 0
    private var lastDragPoint: NSPoint?
    private var isWindowing = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Where the image is drawn: aspect-correct (physical size), centred.
    var imageRect: CGRect {
        guard physicalSize.width > 0, physicalSize.height > 0 else { return .zero }
        let area = bounds.insetBy(dx: 24, dy: 30)
        let scale = min(area.width / physicalSize.width, area.height / physicalSize.height)
        let size = CGSize(width: physicalSize.width * scale, height: physicalSize.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(bounds)

        let rect = imageRect
        if let image, rect.width > 0 {
            ctx.interpolationQuality = smooth ? .high : .none
            ctx.draw(image, in: rect)
        }

        if let c = crosshair, rect.width > 0, pixelSize.width > 0, pixelSize.height > 0 {
            let x = rect.minX + (c.x + 0.5) / pixelSize.width * rect.width
            let y = rect.maxY - (c.y + 0.5) / pixelSize.height * rect.height
            let gap: CGFloat = 10
            ctx.setLineWidth(1)
            ctx.setStrokeColor(horizontalLineColor.withAlphaComponent(0.8).cgColor)
            ctx.strokeLineSegments(between: [
                CGPoint(x: rect.minX, y: y), CGPoint(x: x - gap, y: y),
                CGPoint(x: x + gap, y: y), CGPoint(x: rect.maxX, y: y),
            ])
            ctx.setStrokeColor(verticalLineColor.withAlphaComponent(0.8).cgColor)
            ctx.strokeLineSegments(between: [
                CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: y - gap),
                CGPoint(x: x, y: y + gap), CGPoint(x: x, y: rect.maxY),
            ])
            // small centre ring
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.strokeEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        }

        drawText(rect)
    }

    private func drawText(_ rect: CGRect) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.5),
        ]
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.7),
        ]
        func put(_ text: String, _ attrs: [NSAttributedString.Key: Any], at point: (CGSize) -> CGPoint) {
            guard !text.isEmpty else { return }
            let s = NSAttributedString(string: text, attributes: attrs)
            s.draw(at: point(s.size()))
        }
        let b = bounds
        let r = rect.width > 0 ? rect : b
        put(labels.left, labelAttrs) { CGPoint(x: max(b.minX + 8, r.minX - $0.width - 6), y: b.midY - $0.height / 2) }
        put(labels.right, labelAttrs) { CGPoint(x: min(b.maxX - 8 - $0.width, r.maxX + 6), y: b.midY - $0.height / 2) }
        put(labels.top, labelAttrs) { CGPoint(x: b.midX - $0.width / 2, y: min(b.maxY - 6 - $0.height, r.maxY + 4)) }
        put(labels.bottom, labelAttrs) { CGPoint(x: b.midX - $0.width / 2, y: max(b.minY + 6, r.minY - $0.height - 4)) }
        put(title, infoAttrs) { CGPoint(x: b.minX + 10, y: b.maxY - 8 - $0.height) }
        put(detail, infoAttrs) { CGPoint(x: b.maxX - 10 - $0.width, y: b.maxY - 8 - $0.height) }
    }

    // MARK: Mouse

    private func pixel(at point: NSPoint, clamp: Bool) -> (Int, Int)? {
        let r = imageRect
        guard r.width > 0, r.height > 0, pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let fx = (point.x - r.minX) / r.width
        let fy = (r.maxY - point.y) / r.height
        if !clamp && (fx < 0 || fx >= 1 || fy < 0 || fy >= 1) { return nil }
        let col = min(max(Int(fx * pixelSize.width), 0), Int(pixelSize.width) - 1)
        let row = min(max(Int(fy * pixelSize.height), 0), Int(pixelSize.height) - 1)
        return (col, row)
    }

    private func location(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        let p = location(event)
        if event.modifierFlags.contains(.option) {
            isWindowing = true
            lastDragPoint = p
        } else {
            isWindowing = false
            select(p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        if isWindowing { windowDrag(to: p) } else { select(p) }
        onHover?(pixel(at: p, clamp: false))
    }

    override func mouseUp(with event: NSEvent) {
        isWindowing = false
        lastDragPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        lastDragPoint = location(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        windowDrag(to: location(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        lastDragPoint = nil
    }

    private func select(_ point: NSPoint) {
        if let px = pixel(at: point, clamp: true) { onSelect?(px.0, px.1) }
    }

    private func windowDrag(to point: NSPoint) {
        if let last = lastDragPoint { onWindowDrag?(point.x - last.x, point.y - last.y) }
        lastDragPoint = point
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 6 : event.scrollingDeltaY
        scrollAccumulator += delta
        let steps = Int(scrollAccumulator)
        if steps != 0 {
            scrollAccumulator -= CGFloat(steps)
            onScroll?(steps)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126, 124: onScroll?(1)  // up, right
        case 125, 123: onScroll?(-1) // down, left
        default: super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(pixel(at: location(event), clamp: false))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }
}

struct SliceView: NSViewRepresentable {
    var image: CGImage?
    var physicalSize: CGSize
    var pixelSize: CGSize
    var crosshair: CGPoint?
    var labels: OrientationLabels = .none
    var title: String = ""
    var detail: String = ""
    var smooth: Bool = true
    var horizontalLineColor: NSColor = .systemTeal
    var verticalLineColor: NSColor = .systemTeal
    var onSelect: ((Int, Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onWindowDrag: ((CGFloat, CGFloat) -> Void)?
    var onHover: (((Int, Int)?) -> Void)?
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> SliceNSView { SliceNSView() }

    func updateNSView(_ view: SliceNSView, context: Context) {
        view.image = image
        view.physicalSize = physicalSize
        view.pixelSize = pixelSize
        view.crosshair = crosshair
        view.labels = labels
        view.title = title
        view.detail = detail
        view.smooth = smooth
        view.horizontalLineColor = horizontalLineColor
        view.verticalLineColor = verticalLineColor
        view.backgroundColor = NSColor(red: 0.035, green: 0.04, blue: 0.05, alpha: 1)
        view.onSelect = onSelect
        view.onScroll = onScroll
        view.onWindowDrag = onWindowDrag
        view.onHover = onHover
        view.onDoubleClick = onDoubleClick
        view.needsDisplay = true
    }
}
