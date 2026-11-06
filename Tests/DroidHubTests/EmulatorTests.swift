import Foundation
import Testing
@testable import DroidHub

// Trimmed from Android Studio's sdklib nexus.xml.
@Test func parsesDeviceProfile() throws {
    let xml = """
    <d:devices xmlns:d="http://schemas.android.com/sdk/devices/7">
      <d:device>
        <d:name>Pixel Tablet</d:name>
        <d:id>pixel_tablet</d:id>
        <d:manufacturer>Google</d:manufacturer>
        <d:playstore-enabled>true</d:playstore-enabled>
        <d:hardware>
          <d:screen>
            <d:pixel-density>xhdpi</d:pixel-density>
            <d:dimensions><d:x-dimension>2560</d:x-dimension><d:y-dimension>1600</d:y-dimension></d:dimensions>
          </d:screen>
          <d:skin>pixel_tablet</d:skin>
        </d:hardware>
        <d:state name="Portrait"><d:screen-orientation>port</d:screen-orientation></d:state>
        <d:state name="Landscape" default="true"><d:screen-orientation>land</d:screen-orientation></d:state>
      </d:device>
    </d:devices>
    """
    let doc = try XMLDocument(data: Data(xml.utf8))
    let node = try #require(try doc.nodes(forXPath: "//*[local-name()='device']").first)
    let profile = try #require(DeviceProfile(node))
    #expect(profile.id == "pixel_tablet")
    #expect(profile.density == 320)
    #expect(profile.width == 2560 && profile.height == 1600)
    #expect(profile.landscape)
    #expect(DeviceProfile.dpi("420dpi") == 420)
}

@Test func writesAvdConfig() {
    let image = SystemImage(id: "system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/", target: "android-37.0", api: "37.0",
                            abi: "arm64-v8a", tagIDs: "google_apis_playstore,page_size_16kb", tagDisplays: "Google APIs PlayStore,Page Size 16KB")
    let xml = "<d:device xmlns:d=\"x\"><d:name>Pixel 10</d:name><d:id>pixel_10</d:id><d:manufacturer>Google</d:manufacturer><d:playstore-enabled>true</d:playstore-enabled><d:pixel-density>420dpi</d:pixel-density><d:x-dimension>1080</d:x-dimension><d:y-dimension>2424</d:y-dimension></d:device>"
    let node = try! XMLDocument(data: Data(xml.utf8)).rootElement()!
    let config = AVD.config(name: "Pixel 10 (2)", device: DeviceProfile(node)!, image: image, skinPath: nil)
    for line in ["AvdId=Pixel_10__2_", "avd.ini.displayname=Pixel 10 (2)", "hw.lcd.density=420", "hw.cpu.arch=arm64",
                 "PlayStore.enabled=true", "tag.id=google_apis_playstore", "image.sysdir.1=system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/",
                 "skin.name=1080x2424", "target=android-37.0"] {
        #expect(config.contains(line + "\n"), "missing \(line)")
    }
}

// Pixel 10 Pro Fold, trimmed from Android Studio's sdklib nexus.xml.
@Test func writesHingeForFoldables() throws {
    let xml = """
    <d:device xmlns:d="http://schemas.android.com/sdk/devices/7">
      <d:name>Pixel 10 Pro Fold</d:name>
      <d:id>pixel_10_pro_fold</d:id>
      <d:hardware>
        <d:screen>
          <d:pixel-density>390dpi</d:pixel-density>
          <d:dimensions><d:x-dimension>2076</d:x-dimension><d:y-dimension>2152</d:y-dimension></d:dimensions>
          <d:foldable-region>
            <d:x-folded-offset>0</d:x-folded-offset><d:y-folded-offset>0</d:y-folded-offset>
            <d:x-folded-dimension>1080</d:x-folded-dimension><d:y-folded-dimension>2364</d:y-folded-dimension>
          </d:foldable-region>
        </d:screen>
        <d:hinge>
          <d:count>1</d:count><d:type>1</d:type><d:sub-type>1</d:sub-type><d:ranges>0-180</d:ranges><d:defaults>180</d:defaults>
          <d:areas>1038-0-0-2152</d:areas><d:change-orientation-on-fold>1</d:change-orientation-on-fold>
          <d:posture-list>1, 2, 3</d:posture-list>
          <d:hinge-angles-posture-definitions>0-30, 30-150, 150-180</d:hinge-angles-posture-definitions>
        </d:hinge>
      </d:hardware>
    </d:device>
    """
    let profile = try #require(try XMLDocument(data: Data(xml.utf8)).rootElement().flatMap(DeviceProfile.init))
    let image = SystemImage(id: "system-images/android-37.2/google_apis/arm64-v8a/", target: "android-37.2", api: "37.2",
                            abi: "arm64-v8a", tagIDs: "google_apis", tagDisplays: "Google APIs")
    let lines = AVD.config(name: "Fold", device: profile, image: image, skinPath: nil).split(separator: "\n")
    // Traps if a key is written twice.
    let config = Dictionary(uniqueKeysWithValues: lines.map { line in
        let kv = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(kv[0]), String(kv[1]))
    })
    // What Android Studio wrote for the same profile.
    let expected = [
        "hw.sensor.hinge": "yes", "hw.sensor.hinge.count": "1", "hw.sensor.hinge.type": "1", "hw.sensor.hinge.sub_type": "1",
        "hw.sensor.hinge.ranges": "0-180", "hw.sensor.hinge.defaults": "180", "hw.sensor.hinge.areas": "1038-0-0-2152",
        "hw.sensor.posture_list": "1, 2, 3", "hw.sensor.hinge_angles_posture_definitions": "0-30, 30-150, 150-180",
        "hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture": "1",
        "hw.displayRegion.0.1.xOffset": "0", "hw.displayRegion.0.1.yOffset": "0",
        "hw.displayRegion.0.1.width": "1080", "hw.displayRegion.0.1.height": "2364",
        "hw.lcd.width": "2076", "hw.lcd.height": "2152",
    ]
    for (key, value) in expected { #expect(config[key] == value, "\(key)") }
    let hinge = try #require(Hinge(config: config))
    #expect(hinge.range == 0...180)
    #expect(hinge.postures == [.closed, .halfOpen, .open])
    #expect([0, 30, 90, 150, 180].map(hinge.posture) == [.closed, .closed, .halfOpen, .halfOpen, .open])
}

@Test func phonesHaveNoHinge() throws {
    let xml = "<d:device xmlns:d=\"x\"><d:name>Pixel 10</d:name><d:id>pixel_10</d:id><d:pixel-density>420dpi</d:pixel-density><d:x-dimension>1080</d:x-dimension><d:y-dimension>2424</d:y-dimension></d:device>"
    let profile = try #require(try XMLDocument(data: Data(xml.utf8)).rootElement().flatMap(DeviceProfile.init))
    #expect(profile.hinge.isEmpty)
    #expect(Hinge(config: ["hw.sensor.hinge": "no", "hw.sensor.hinge.ranges": "0-180", "hw.sensor.posture_list": "1, 2, 3"]) == nil)
    // 8" Fold-out
    let out = try #require(Hinge(config: ["hw.sensor.hinge": "yes", "hw.sensor.hinge.ranges": "180-360", "hw.sensor.posture_list": "3, 4",
                                          "hw.sensor.hinge_angles_posture_definitions": "180-330, 330-360"]))
    #expect(out.postures == [.open, .flipped] && out.posture(at: 340) == .flipped)
    #expect(Hinge.angle(from: "hinge-angle0 = 90\nOK\n") == 90)
    #expect(Hinge.angle(from: "KO: bad sensor") == nil)
}
