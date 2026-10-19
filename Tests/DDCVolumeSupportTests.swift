// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind monitor speaker volume: the step grid, which audio
/// outputs belong to a display, which display an output plays through, mute
/// and key ownership. No display or audio device is touched.
enum DDCVolumeSupportTests {
    static func run(_ suite: TestSuite) {
        steps(suite)
        transport(suite)
        matching(suite)
        mute(suite)
        keys(suite)
    }

    private static func steps(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        suite.expect(S.volumeCode == 0x62, "speaker volume is VCP 0x62")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 1, fine: false) == 56,
                     "a step up from 50 of 100 lands on the next sixteenth (56)")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: -1, fine: false) == 44,
                     "a step down from 50 of 100 lands on the previous sixteenth (44)")
        suite.expect(S.steppedValue(current: 100, maximum: 100, direction: 1, fine: false) == 100,
                     "volume never passes the monitor's maximum")
        suite.expect(S.steppedValue(current: 0, maximum: 100, direction: -1, fine: false) == 0,
                     "volume never goes below zero")
        suite.expect(S.steppedValue(current: 3, maximum: 100, direction: 1, fine: false) == 6,
                     "a level off the grid snaps to the nearest step before moving")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 1, fine: true) == 52,
                     "Option-Shift moves a quarter step")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 3, fine: false) == 69,
                     "coalesced key repeats move several steps at once")
        suite.expect(S.steppedValue(current: 10, maximum: 0, direction: 1, fine: false) == 19,
                     "a monitor reporting no range is treated as 0-100")
        suite.expect(S.steppedValue(current: 200, maximum: 100, direction: -1, fine: false) == 94,
                     "a reading above the maximum is clamped before stepping")
        suite.expectClose(S.level(value: 25, maximum: 50), 0.5, "level is value over maximum")
        suite.expectClose(S.level(value: 80, maximum: 0), 0.8, "a missing range reads as 0-100")
    }

    private static func transport(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        suite.expect(S.isDisplayAudio(transportType: 0x6470_7274), "DisplayPort audio is display audio")
        suite.expect(S.isDisplayAudio(transportType: 0x6864_6D69), "HDMI audio is display audio")
        suite.expect(!S.isDisplayAudio(transportType: 0x7573_6220), "USB audio keeps the system keys")
        suite.expect(!S.isDisplayAudio(transportType: 0x626C_7468), "Bluetooth audio keeps the system keys")
        suite.expect(!S.isDisplayAudio(transportType: 0x626C_746E), "built-in audio keeps the system keys")
    }

    private static func matching(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        let two: [(id: UInt32, name: String)] = [(1, "LG HDR 4K"), (2, "DELL U2723QE")]
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: two) == 1,
                     "an output named after a display plays through it")
        suite.expect(S.matchDisplay(outputName: "dell u2723qe", displays: two) == 2,
                     "names match regardless of case and punctuation")
        suite.expect(S.matchDisplay(outputName: "U2723QE", displays: two) == 2,
                     "a name missing the vendor prefix still matches")
        suite.expect(S.matchDisplay(outputName: "Studio Display", displays: two) == nil,
                     "with two displays and no matching name the keys stay with the system")
        suite.expect(S.matchDisplay(outputName: "Monitor", displays: [(7, "LG HDR 4K")]) == 7,
                     "a single DDC display is the only place display audio can play")
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: []) == nil,
                     "no DDC display, no target")
        let same: [(id: UInt32, name: String)] = [(1, "LG HDR 4K"), (2, "LG HDR 4K")]
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: same) == nil,
                     "two identical monitors are ambiguous and left to the system")
    }

    private static func mute(_ suite: TestSuite) {
        var state = DDCVolumeSupport.MuteState()
        suite.expect(!state.isMuted, "a display starts unmuted")
        suite.expect(state.toggle(current: 40, maximum: 100) == 0, "muting writes zero")
        suite.expect(state.isMuted, "muting is remembered")
        suite.expect(state.toggle(current: 0, maximum: 100) == 40, "unmuting restores the previous level")
        suite.expect(!state.isMuted, "unmuting clears the state")

        _ = state.toggle(current: 30, maximum: 100)
        suite.expect(state.unmuteForStep(current: 0) == 30,
                     "a volume key while muted steps from the remembered level")
        suite.expect(!state.isMuted, "a volume key unmutes")

        _ = state.toggle(current: 0, maximum: 100)
        suite.expect(state.toggle(current: 0, maximum: 100) == 6,
                     "unmuting what was muted from silence restores one step, not silence")
    }

    private static func keys(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        func data1(_ code: Int, _ state: Int, repeated: Bool = false) -> Int {
            (code << 16) | (state << 8) | (repeated ? 1 : 0)
        }
        suite.expect(S.keyPress(fromData1: data1(0, 0x0a)) == S.KeyPress(key: .volumeUp, isDown: true, isRepeat: false),
                     "volume up press parses")
        suite.expect(S.keyPress(fromData1: data1(1, 0x0b)) == S.KeyPress(key: .volumeDown, isDown: false, isRepeat: false),
                     "volume down release parses")
        suite.expect(S.keyPress(fromData1: data1(7, 0x0a, repeated: true)) == S.KeyPress(key: .mute, isDown: true, isRepeat: true),
                     "mute repeat parses")
        suite.expect(S.keyPress(fromData1: data1(2, 0x0a)) == nil, "brightness keys are not volume keys")
        suite.expect(S.keyPress(fromData1: data1(16, 0x0a)) == nil, "play is not a volume key")
        suite.expect(S.keyPress(fromData1: data1(0, 0x05)) == nil, "unknown key states are ignored")

        var ownership = S.KeyOwnership()
        suite.expect(!ownership.releases(.volumeUp), "a release of a press left to the system goes to the system")
        ownership.claim(.volumeUp)
        suite.expect(ownership.releases(.volumeUp), "a release of a claimed press is taken too")
        suite.expect(!ownership.releases(.volumeUp), "each claim covers one release")
    }
}
