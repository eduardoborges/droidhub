import CoreGraphics
import Testing
@testable import DroidHub

@Test func cornersComeFromTheDisplay() {
    let dump = """
      DisplayDeviceInfo{"Built-in Screen": uniqueId="local:1", 2076 x 2152, modeId 1, roundedCorners RoundedCorners{[RoundedCorner{position=TopLeft, radius=85, center=Point(85, 85)}]}, installOrientation 0}
      DisplayDeviceInfo{"Built-in Screen": uniqueId="local:2", 1080 x 2364, modeId 2, roundedCorners RoundedCorners{[RoundedCorner{position=TopLeft, radius=115, center=Point(115, 115)}]}, installOrientation 0}
      DisplayDeviceInfo{"scrcpy": uniqueId="virtual:scrcpy", 2076 x 2152, modeId 3, roundedCorners null, installOrientation 0}
    """
    let corners = ScreenCorner.parse(dump)
    #expect(corners == [ScreenCorner(size: CGSize(width: 2076, height: 2152), radius: 85), ScreenCorner(size: CGSize(width: 1080, height: 2364), radius: 115)])
    #expect(corners.radius(for: CGSize(width: 2076, height: 2152)) == 85)
    #expect(corners.radius(for: CGSize(width: 2364, height: 1080)) == 115, "turned")
    #expect(corners.radius(for: CGSize(width: 540, height: 1182)) == 57.5, "scaled down")
    #expect(corners.radius(for: CGSize(width: 1600, height: 2560)) == 2560 * 0.045, "no display that shape")
}
