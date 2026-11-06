import CoreGraphics
import SwiftUI
import Testing
@testable import DroidHub

@Test func bendMapsClicksBack() {
    let size = CGSize(width: 400, height: 420)
    for vertical in [true, false] {
        let bend = Bend(angle: 40, vertical: vertical)
        for p in [CGPoint(x: 50, y: 60), CGPoint(x: 350, y: 300), CGPoint(x: 199, y: 10), CGPoint(x: 210, y: 400)] {
            let half = (vertical ? p.x <= 200 : p.y <= 210) ? 0 : 1
            let back = bend.unproject(p.applying(bend.transform(half: half, size: size)), size: size)
            #expect(abs(back.x - p.x) < 0.01 && abs(back.y - p.y) < 0.01, "\(vertical) \(p)")
        }
    }
}

@Test func bendIsAValleyThatFits() {
    let size = CGSize(width: 400, height: 400)
    let book = Bend(angle: 45, vertical: true).transform(half: 0, size: size)
    let corner = CGPoint.zero.applying(book), hinge = CGPoint(x: 200, y: 0).applying(book)
    #expect(corner.x > 0 && corner.y < hinge.y && corner.y > -0.01)
    let tabletop = Bend(angle: 45, vertical: false).transform(half: 0, size: size)
    let top = CGPoint.zero.applying(tabletop), side = CGPoint(x: 0, y: 200).applying(tabletop)
    #expect(top.y > 0 && top.x < side.x && top.x > -0.01)
}

@Test func bendFollowsTheScreenShowing() throws {
    let hinge = try #require(Hinge(config: [
        "hw.sensor.hinge": "yes", "hw.sensor.hinge.ranges": "0-180", "hw.sensor.posture_list": "1, 2, 3",
        "hw.sensor.hinge_angles_posture_definitions": "0-30, 30-150, 150-180", "hw.sensor.hinge.areas": "1038-0-0-2152",
        "hw.lcd.width": "2076", "hw.lcd.height": "2152",
    ]))
    #expect(hinge.bend(angle: 90, video: CGSize(width: 2076, height: 2152)) == Bend(angle: 45, vertical: true))
    #expect(hinge.bend(angle: 90, video: CGSize(width: 2152, height: 2076)) == Bend(angle: 45, vertical: false))
    #expect(hinge.bend(angle: 180, video: CGSize(width: 2072, height: 2152)).angle == 0)
    #expect(hinge.bend(angle: 10, video: CGSize(width: 2076, height: 2152)).angle == 60)
    #expect(hinge.bend(angle: 0, video: CGSize(width: 1080, height: 2364)).angle == 0)
}

@Test func sidesShowPastTheOuterEdges() {
    let size = CGSize(width: 400, height: 400), depth = 14.0
    for vertical in [true, false] {
        let bend = Bend(angle: 45, vertical: vertical)
        for i in 0..<2 {
            let front = bend.transform(half: i, size: size), back = bend.transform(half: i, size: size, depth: depth)
            let outer = vertical ? CGPoint(x: i == 0 ? 0 : 400, y: 200) : CGPoint(x: 200, y: i == 0 ? 0 : 400)
            let f = outer.applying(front), b = outer.applying(back)
            let out = (vertical ? b.x - f.x : b.y - f.y) * (i == 0 ? -1 : 1)
            #expect(out > depth * 0.5 && out < depth, "\(vertical) \(i): \(out)")
            let hinge = CGPoint(x: 200, y: 200), h = hinge.applying(back), hf = hinge.applying(front)
            #expect((vertical ? h.x - hf.x : h.y - hf.y) * (i == 0 ? -1 : 1) > 0, "hidden behind its own half at the hinge, \(vertical) \(i)")
        }
    }
}
