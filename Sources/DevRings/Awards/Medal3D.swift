import AppKit
import os
import DevRingsCore
import SceneKit
import SwiftUI

/// A medal rendered in SceneKit. `tilt` leans it toward the pointer and `spin` turns it about its vertical
/// axis; both animate in SceneKit, so pass `animated` when the change should ease rather than track.
struct MedalView: NSViewRepresentable {
    let kind: AwardKind
    let earned: Bool
    var back: String?
    var tilt = CGSize.zero
    var spin = 0.0
    var animated = false
    var spinIn = false

    func makeCoordinator() -> FirstFrame { FirstFrame() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        // Hidden until SceneKit has drawn a frame, or the empty Metal layer flashes white first.
        view.alphaValue = 0
        context.coordinator.reveal = { [weak view] in
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; view?.animator().alphaValue = 1 }
        }
        view.delegate = context.coordinator
        view.scene = MedalScene.make(kind: kind, earned: earned, back: back)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        if spinIn, let medal = view.scene?.rootNode.childNode(withName: "medal", recursively: false) {
            let action = SCNAction.rotateBy(x: 0, y: .pi * 4, z: 0, duration: 1.6)
            action.timingMode = .easeOut
            medal.runAction(action)
        }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard let medal = view.scene?.rootNode.childNode(withName: "medal", recursively: false), !medal.hasActions else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0.08
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: animated ? .easeOut : .linear)
        medal.eulerAngles = SCNVector3(MedalScene.restingPitch - tilt.height * 0.45, MedalScene.restingYaw + tilt.width * 0.6 + spin, 0)
        SCNTransaction.commit()
    }
}

final class FirstFrame: NSObject, SCNSceneRendererDelegate {
    var reveal: (@MainActor @Sendable () -> Void)?
    private let drawn = OSAllocatedUnfairLock(initialState: false)

    nonisolated func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let first = drawn.withLock { done in
            defer { done = true }
            return !done
        }
        guard first, let reveal else { return }
        Task { @MainActor in reveal() }
    }
}

enum MedalScene {
    /// Turned slightly away from the viewer at rest, so the rim's depth catches the light.
    static let restingPitch: CGFloat = -0.2
    static let restingYaw: CGFloat = 0.32

    @MainActor static func make(kind: AwardKind, earned: Bool, back: String?) -> SCNScene {
        let scene = SCNScene()
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.25

        let finish = earned ? kind.finish : .locked
        let medal = SCNNode()
        medal.name = "medal"
        medal.eulerAngles = SCNVector3(restingPitch, restingYaw, 0)

        let body = SCNShape(path: bezier(outline(kind.sides, radius: 1)), extrusionDepth: 0.16)
        body.chamferRadius = 0.05
        body.materials = [metal(finish.rim, roughness: 0.24)]
        medal.addChildNode(SCNNode(geometry: body))

        let rim = SCNShape(path: bezier(outline(kind.sides, radius: 1).subtracting(outline(kind.sides, radius: 0.82))), extrusionDepth: 0.1)
        rim.chamferRadius = 0.03
        rim.materials = [metal(finish.rim, roughness: 0.18)]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position.z = 0.08
        medal.addChildNode(rimNode)

        let face = SCNShape(path: bezier(outline(kind.sides, radius: 0.84)), extrusionDepth: 0.02)
        face.materials = [enamel(finish.face)]
        let faceNode = SCNNode(geometry: face)
        faceNode.position.z = 0.085
        medal.addChildNode(faceNode)

        let emblem = SCNShape(path: bezier(kind.emblemPath, fitting: kind.emblemPath.boundingBoxOfPath.width > kind.emblemPath.boundingBoxOfPath.height * 1.3 ? 1.05 : 0.86),
                              extrusionDepth: 0.1)
        emblem.chamferRadius = 0.022
        // A frosted face with polished bevels, as struck medals have; a mirror face would reflect the dark
        // studio behind the camera and read as black. SCNShape's elements: front, back, sides, then chamfers.
        let frosted = metal(finish.emblem, roughness: 0.55)
        let polished = metal(finish.emblem, roughness: 0.15)
        emblem.materials = [frosted, frosted, polished, polished, polished]
        let emblemNode = SCNNode(geometry: emblem)
        emblemNode.position.z = 0.135
        medal.addChildNode(emblemNode)

        if let back {
            let lines = back.split(separator: "\n").map(String.init)
            let engraving = CGMutablePath()
            for (i, line) in lines.enumerated() {
                let path = textPath(line, size: 100, weight: i == 0 ? .bold : .medium, rounded: false)
                let box = path.boundingBoxOfPath
                let scale = (i == 0 ? 0.13 : 0.1) / 70.0
                let y = CGFloat(lines.count - 1) * 0.11 - CGFloat(i) * 0.24
                var transform = CGAffineTransform(translationX: 0, y: y).scaledBy(x: scale, y: scale).translatedBy(x: -box.midX, y: -box.midY)
                if let placed = path.copy(using: &transform) { engraving.addPath(placed) }
            }
            let text = SCNShape(path: bezier(engraving), extrusionDepth: 0.03)
            text.materials = [metal(finish.rim, roughness: 0.4)]
            let textNode = SCNNode(geometry: text)
            textNode.position.z = -0.095
            textNode.eulerAngles.y = .pi
            medal.addChildNode(textNode)
        }

        scene.rootNode.addChildNode(medal)

        let camera = SCNCamera()
        camera.fieldOfView = 21
        camera.wantsHDR = true
        camera.bloomIntensity = earned ? 0.25 : 0
        camera.bloomThreshold = 0.9
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 6.3)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(keyNode)
        return scene
    }

    // MARK: Materials

    private static func metal(_ color: NSColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 1.0
        m.roughness.contents = roughness
        return m
    }

    private static func enamel(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 0.0
        m.roughness.contents = 0.5
        m.clearCoat.contents = 0.45
        m.clearCoatRoughness.contents = 0.04
        return m
    }

    /// An equirectangular "photo studio": soft boxes overhead and to the sides over a dark floor,
    /// which is what gives polished metal its bright edges and dark mid-tones.
    @MainActor private static let studio: NSImage = {
        let size = NSSize(width: 1024, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0.04, alpha: 1), NSColor(white: 0.12, alpha: 1), NSColor(white: 0.28, alpha: 1)],
                       atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)?.draw(in: rect, angle: 90)
            func softBox(_ box: NSRect, _ white: CGFloat) {
                NSGradient(colors: [NSColor(white: white, alpha: 1), NSColor(white: white, alpha: 0)])?
                    .draw(in: NSBezierPath(ovalIn: box), relativeCenterPosition: .zero)
            }
            softBox(NSRect(x: 360, y: 400, width: 300, height: 110), 1.0)
            softBox(NSRect(x: 60, y: 250, width: 110, height: 180), 1.0)
            softBox(NSRect(x: 850, y: 260, width: 90, height: 160), 0.8)
            softBox(NSRect(x: 500, y: 290, width: 70, height: 50), 0.9)
            return true
        }
    }()

    // MARK: Paths

    static func outline(_ sides: Int, radius: CGFloat) -> CGPath {
        MedalShape(sides: sides).path(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
    }

    /// Scales `path` to `size` across its longer side, centred on the origin, with its outer contour wound
    /// anticlockwise as SceneKit expects. Font glyphs wind the other way and would extrude inside out.
    static func bezier(_ path: CGPath, fitting size: CGFloat? = nil) -> NSBezierPath {
        var path = path
        if let size {
            let box = path.boundingBoxOfPath
            let scale = size / max(box.width, box.height)
            var transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.midX, y: -box.midY)
            path = path.copy(using: &transform) ?? path
        }
        var bezier = NSBezierPath(cgPath: path)
        if outerArea(of: bezier) < 0 { bezier = bezier.reversed }
        bezier.flatness = 0.002
        return bezier
    }

    /// Signed area of the largest contour: positive when it runs anticlockwise.
    private static func outerArea(of path: NSBezierPath) -> CGFloat {
        let flat = path.flattened
        var largest: CGFloat = 0
        var area: CGFloat = 0
        var start = CGPoint.zero
        var previous = CGPoint.zero
        var points = [NSPoint](repeating: .zero, count: 3)
        func close() {
            area += previous.x * start.y - start.x * previous.y
            if abs(area) > abs(largest) { largest = area }
            area = 0
        }
        for i in 0..<flat.elementCount {
            switch flat.element(at: i, associatedPoints: &points) {
            case .moveTo:
                if i > 0 { close() }
                start = points[0]
                previous = points[0]
            case .lineTo:
                area += previous.x * points[0].y - points[0].x * previous.y
                previous = points[0]
            case .closePath:
                close()
                previous = start
            default:
                break
            }
        }
        close()
        return largest / 2
    }

    static func textPath(_ string: String, size: CGFloat, weight: NSFont.Weight, rounded: Bool) -> CGPath {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName as String] else { continue }
            let runFont = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        // San Francisco's outlines overlap inside a glyph (it's a variable font), and SceneKit silently drops
        // shapes whose contours overlap, which loses letters like "e" and "a". Merging them first fixes that.
        return path.normalized()
    }
}

struct MedalFinish {
    let rim: NSColor
    let face: NSColor
    let emblem: NSColor

    static let gold = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.36, alpha: 1)
    static let silver = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    static let locked = MedalFinish(rim: NSColor(white: 0.32, alpha: 1), face: NSColor(white: 0.06, alpha: 1), emblem: NSColor(white: 0.45, alpha: 1))
}

extension AwardKind {
    var sides: Int {
        switch self {
        case .perfectWeek, .reviewerOfTheWeek: 6
        case .streak5, .streak10, .streak25, .streak50, .streak100: 8
        default: 0
        }
    }

    var finish: MedalFinish {
        func face(_ hex: UInt32) -> NSColor { NSColor(Color(hex: hex)) }
        return switch self {
        case .firstRing: MedalFinish(rim: MedalFinish.silver, face: face(0x1B6E0C), emblem: MedalFinish.silver)
        case .perfectDay: MedalFinish(rim: MedalFinish.gold, face: face(0x8A0629), emblem: MedalFinish.gold)
        case .doubleShip: MedalFinish(rim: MedalFinish.silver, face: face(0x96082F), emblem: MedalFinish.silver)
        case .tripleShip: MedalFinish(rim: MedalFinish.gold, face: face(0x96082F), emblem: MedalFinish.gold)
        case .newBest: MedalFinish(rim: MedalFinish.gold, face: face(0x45137D), emblem: MedalFinish.gold)
        case .perfectWeek: MedalFinish(rim: MedalFinish.gold, face: face(0x063E99), emblem: MedalFinish.gold)
        case .reviewerOfTheWeek: MedalFinish(rim: MedalFinish.silver, face: face(0x07636D), emblem: MedalFinish.silver)
        default: MedalFinish(rim: MedalFinish.gold, face: face(0xA33A04), emblem: MedalFinish.gold)
        }
    }

    /// Emblems are built as vector outlines so they can be extruded; SF Symbols don't expose paths.
    var emblemPath: CGPath {
        switch self {
        case .doubleShip: return MedalScene.textPath("2×", size: 100, weight: .heavy, rounded: true)
        case .tripleShip: return MedalScene.textPath("3×", size: 100, weight: .heavy, rounded: true)
        case .perfectDay: return Emblem.check
        case .newBest: return Emblem.star
        case .firstRing: return Emblem.rings
        case .perfectWeek: return Emblem.calendar
        case .reviewerOfTheWeek: return Emblem.bubble
        default: return MedalScene.textPath(String(streakLength ?? 0), size: 100, weight: .heavy, rounded: true)
        }
    }
}

private enum Emblem {
    static var check: CGPath {
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 0, y: 0.5))
        line.addLine(to: CGPoint(x: 0.36, y: 0.14))
        line.addLine(to: CGPoint(x: 1.0, y: 0.92))
        return line.copy(strokingWithWidth: 0.24, lineCap: .round, lineJoin: .round, miterLimit: 4).normalized()
    }

    static var star: CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 1 : 0.46
            let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: r * cos(a), y: r * sin(a))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static var rings: CGPath {
        func circle(_ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil) }
        return circle(1).subtracting(circle(0.72)).union(circle(0.5).subtracting(circle(0.24)))
    }

    static var calendar: CGPath {
        let frame = CGPath(roundedRect: CGRect(x: -1, y: -0.9, width: 2, height: 1.8), cornerWidth: 0.28, cornerHeight: 0.28, transform: nil)
        let inside = CGPath(roundedRect: CGRect(x: -0.8, y: -0.72, width: 1.6, height: 1.12), cornerWidth: 0.1, cornerHeight: 0.1, transform: nil)
        var path = frame.subtracting(inside)
        for row in 0..<2 {
            for column in 0..<3 {
                let cell = CGPath(roundedRect: CGRect(x: -0.62 + CGFloat(column) * 0.46, y: -0.56 + CGFloat(row) * 0.46, width: 0.32, height: 0.3),
                                  cornerWidth: 0.06, cornerHeight: 0.06, transform: nil)
                path = path.union(cell)
            }
        }
        return path
    }

    static var bubble: CGPath {
        let body = CGPath(roundedRect: CGRect(x: -1, y: -0.5, width: 2, height: 1.4), cornerWidth: 0.42, cornerHeight: 0.42, transform: nil)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -0.6, y: -0.3))
        tail.addLine(to: CGPoint(x: -0.78, y: -1.0))
        tail.addLine(to: CGPoint(x: -0.1, y: -0.4))
        tail.closeSubpath()
        var path = body.union(tail)
        for (i, width) in [1.2, 0.8].enumerated() {
            let line = CGPath(roundedRect: CGRect(x: -0.6, y: 0.38 - CGFloat(i) * 0.36, width: width, height: 0.16),
                              cornerWidth: 0.08, cornerHeight: 0.08, transform: nil)
            path = path.subtracting(line)
        }
        return path
    }
}

/// A circle, or a polygon with softened corners.
struct MedalShape: Shape {
    var sides: Int

    func path(in rect: CGRect) -> Path {
        guard sides >= 3 else { return Circle().path(in: rect) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // Hexagons stand on a point; other even polygons get a flat top.
        let offset: CGFloat = sides % 2 == 0 && sides != 6 ? .pi / CGFloat(sides) : 0
        let step: CGFloat = 2 * .pi / CGFloat(sides)
        let points = (0..<sides).map { i -> CGPoint in
            let a: CGFloat = -.pi / 2 + offset + CGFloat(i) * step
            return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        }
        var path = Path()
        let last = points[sides - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for i in 0..<sides {
            path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % sides], radius: r * 0.14)
        }
        path.closeSubpath()
        return path
    }
}
