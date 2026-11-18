import XCTest
@testable import XboxRemote

final class InputPacketEncoderTests: XCTestCase {

    func testClientMetadataLayout() {
        let data = InputPacketEncoder.clientMetadata(sequence: 0, timestampMs: 0, maxTouchpoints: 1)
        XCTAssertEqual(data.count, 15)
        XCTAssertEqual([UInt8](data), [0x08, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01])
    }

    func testGamepadFrameLayout() {
        var state = GamepadState()
        state.buttons = [.a]
        state.leftStick = StickValue(x: 1, y: -0.5)
        state.rightTrigger = 1

        let data = InputPacketEncoder.inputReport(sequence: 5, timestampMs: 0, metadata: [],
                                                  gamepads: [GamepadFrame(index: 0, state: state)])
        let expected: [UInt8] = [
            0x02, 0x00,                         // reportType = Gamepad
            0x05, 0x00, 0x00, 0x00,             // sequence
            0, 0, 0, 0, 0, 0, 0, 0,             // timestamp (f64 0)
            0x01,                               // frame count
            0x00,                               // gamepad index
            0x10, 0x00,                         // buttons: A = 16
            0xFF, 0x7F,                         // LX = 32767
            0x01, 0xC0,                         // LY = -16383
            0x00, 0x00,                         // RX
            0x00, 0x00,                         // RY
            0x00, 0x00,                         // LT
            0xFF, 0xFF,                         // RT = 65535
            0x01, 0x00, 0x00, 0x00,             // physical physicality (LE)
            0x00, 0x00, 0x00, 0x01              // virtual physicality (BE)
        ]
        XCTAssertEqual([UInt8](data), expected)
    }

    func testMetadataAndGamepadCombined() {
        let meta = VideoMetadataFrame(serverDataKey: 1, firstFramePacketArrivalTimeMs: 2, frameSubmittedTimeMs: 3,
                                      frameDecodedTimeMs: 4, frameRenderedTimeMs: 5, framePacketTimeMs: 6, frameDateNowMs: 7)
        let data = InputPacketEncoder.inputReport(sequence: 1, timestampMs: 1, metadata: [meta, meta],
                                                  gamepads: [GamepadFrame(index: 0, state: .neutral)])
        XCTAssertEqual(data.count, 14 + 1 + 28 * 2 + 1 + 23)
        XCTAssertEqual(data[0], 0x03)   // Metadata | Gamepad
        XCTAssertEqual(data[14], 2)     // metadata count
        XCTAssertEqual(data[15], 1)     // first serverDataKey
    }

    func testAxisAndTriggerNormalization() {
        XCTAssertEqual(InputPacketEncoder.normalizeAxis(2), 32767)
        XCTAssertEqual(InputPacketEncoder.normalizeAxis(-2), -32767)
        XCTAssertEqual(InputPacketEncoder.normalizeAxis(0), 0)
        XCTAssertEqual(InputPacketEncoder.normalizeAxis(.nan), 0)
        XCTAssertEqual(InputPacketEncoder.normalizeTrigger(-1), 0)
        XCTAssertEqual(InputPacketEncoder.normalizeTrigger(0.5), 32767)
        XCTAssertEqual(InputPacketEncoder.normalizeTrigger(1.5), 65535)
    }

    func testButtonMasksMatchProtocol() {
        XCTAssertEqual(GamepadButtons.nexus.rawValue, 2)
        XCTAssertEqual(GamepadButtons.menu.rawValue, 4)
        XCTAssertEqual(GamepadButtons.view.rawValue, 8)
        XCTAssertEqual(GamepadButtons.y.rawValue, 128)
        XCTAssertEqual(GamepadButtons.dpadRight.rawValue, 2048)
        XCTAssertEqual(GamepadButtons.rightThumb.rawValue, 32768)
    }

    func testVibrationParse() {
        let bytes: [UInt8] = [128, 0, 0, 0, 50, 100, 0, 25, 0xF4, 0x01, 0x0A, 0x00, 2]
        let report = VibrationReport.parse(Data(bytes))
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.leftMotor, 0.5)
        XCTAssertEqual(report?.rightMotor, 1)
        XCTAssertEqual(report?.rightTriggerMotor, 0.25)
        XCTAssertEqual(report?.durationMs, 500)
        XCTAssertEqual(report?.delayMs, 10)
        XCTAssertEqual(report?.repeatCount, 2)
        XCTAssertNil(VibrationReport.parse(Data([2, 0, 0])))
    }

    func testMergeAndNexusChord() {
        var touch = GamepadState()
        touch.buttons = [.view]
        touch.leftStick = StickValue(x: 0.2, y: 0)
        var pad = GamepadState()
        pad.buttons = [.menu]
        pad.leftStick = StickValue(x: 0, y: 0.9)
        pad.leftTrigger = 0.4

        let merged = GamepadState.merge([touch, pad]).applyingNexusChord()
        XCTAssertEqual(merged.buttons, [.nexus])
        XCTAssertEqual(merged.leftStick, StickValue(x: 0, y: 0.9))
        XCTAssertEqual(merged.leftTrigger, 0.4)
    }

    func testDeadzone() {
        XCTAssertEqual(StickValue(x: 0.05, y: 0).applyingDeadzone(0.1), .zero)
        let v = StickValue(x: 1, y: 0).applyingDeadzone(0.1)
        XCTAssertEqual(v.x, 1, accuracy: 0.0001)
        let half = StickValue(x: 0.55, y: 0).applyingDeadzone(0.1)
        XCTAssertEqual(half.x, 0.5, accuracy: 0.0001)
    }
}
