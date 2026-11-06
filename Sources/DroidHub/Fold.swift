import QuartzCore
import SwiftUI

/// How far a foldable's frame bends on screen. Each half turns `angle` degrees about the hinge, which runs down the middle of the frame.
struct Bend: Equatable {
    var angle: Double
    var vertical: Bool

    static let flat = Bend(angle: 0, vertical: true)
    /// Camera distance in multiples of the frame's longer side. A bigger value looks flatter.
    static let distance = 3.0

    /// Projection for half `i` (0 is the left or top one), in the frame's own coordinates. It shrinks the frame so the edges that come closer still fit.
    func transform(half i: Int, size: CGSize) -> ProjectionTransform {
        let theta = angle * .pi / 180
        let d = Self.distance * max(size.width, size.height)
        let reach = (vertical ? size.width : size.height) / 2
        let scale = theta > 0 ? (d - reach * sin(theta)) / d : 1
        // Both outer edges turn toward the viewer. Left and top sit on opposite sides of their axes, hence the flipped signs.
        let turn = vertical ? CATransform3DMakeRotation(i == 0 ? theta : -theta, 0, 1, 0) : CATransform3DMakeRotation(i == 0 ? -theta : theta, 1, 0, 0)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / d
        let steps = [CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0), turn, perspective,
                     CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)]
        return ProjectionTransform(steps.dropFirst().reduce(steps[0], CATransform3DConcat))
    }

    /// Where a point seen on the bent frame sits on the flat one.
    func unproject(_ p: CGPoint, size: CGSize) -> CGPoint {
        guard angle != 0 else { return p }
        let mid = vertical ? size.width / 2 : size.height / 2
        for i in 0..<2 {
            let q = p.applying(transform(half: i, size: size).inverted())
            let c = vertical ? q.x : q.y
            if i == 0 ? c <= mid : c >= mid { return q }
        }
        return p
    }
}

/// One side of the hinge, padded outward so the side keys stay visible.
struct HalfShape: Shape {
    let half: Int
    let vertical: Bool

    func path(in r: CGRect) -> Path {
        let big = r.insetBy(dx: -r.width, dy: -r.height)
        if vertical {
            return Path(half == 0 ? CGRect(x: big.minX, y: big.minY, width: r.midX - big.minX, height: big.height)
                                  : CGRect(x: r.midX, y: big.minY, width: big.maxX - r.midX, height: big.height))
        }
        return Path(half == 0 ? CGRect(x: big.minX, y: big.minY, width: big.width, height: r.midY - big.minY)
                              : CGRect(x: big.minX, y: r.midY, width: big.width, height: big.maxY - r.midY))
    }
}

/// Animates the bend between hinge angles.
struct FoldEffect: GeometryEffect {
    var bend: Bend
    let half: Int

    var animatableData: Double {
        get { bend.angle }
        set { bend.angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform { bend.transform(half: half, size: size) }
}

extension Hinge {
    /// Each half turns by half of what the hinge is short of flat, up to 60° so the screen stays readable. The outer screen of a closed fold stays flat.
    func bend(angle: Double, video: CGSize) -> Bend {
        // scrcpy aligns the video size to what the encoder wants, which can trim a few pixels.
        func near(_ a: CGSize, _ b: CGSize) -> Bool { abs(a.width - b.width) <= 16 && abs(a.height - b.height) <= 16 }
        let turned = near(video, CGSize(width: display.height, height: display.width)) && !near(video, display)
        guard near(video, display) || turned else { return Bend(angle: 0, vertical: vertical) }
        return Bend(angle: min(max((180 - angle) / 2, -60), 60), vertical: vertical != turned)
    }
}
