import Foundation

/// 输入通道报文类型（位掩码），与串流协议一致。
struct InputReportType: OptionSet, Hashable {
    let rawValue: UInt16
    static let metadata       = InputReportType(rawValue: 1)
    static let gamepad        = InputReportType(rawValue: 2)
    static let pointer        = InputReportType(rawValue: 4)
    static let clientMetadata = InputReportType(rawValue: 8)
    static let serverMetadata = InputReportType(rawValue: 16)
    static let mouse          = InputReportType(rawValue: 32)
    static let keyboard       = InputReportType(rawValue: 64)
    static let vibration      = InputReportType(rawValue: 128)
}

/// 一帧手柄数据
struct GamepadFrame: Equatable {
    var index: UInt8
    var state: GamepadState
}

/// 视频帧元数据（服务器用来估算延迟），每渲染一帧视频产生一条
struct VideoMetadataFrame: Equatable {
    var serverDataKey: UInt32
    var firstFramePacketArrivalTimeMs: UInt32
    var frameSubmittedTimeMs: UInt32
    var frameDecodedTimeMs: UInt32
    var frameRenderedTimeMs: UInt32
    var framePacketTimeMs: UInt32
    var frameDateNowMs: UInt32
}

/// 小端字节写入器
struct ByteWriter {
    private(set) var data = Data()

    init(capacity: Int = 64) { data.reserveCapacity(capacity) }

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func i16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u32BE(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u64BE(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func i32BE(_ v: Int32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    mutating func bytes(_ d: Data) { data.append(d) }
}

/// 输入通道报文编码。字节布局对照开源参考实现 xbox-xcloud-player 的 channel/input/packet.ts。
///
/// 报文头（14 字节）：reportType u16 LE | sequence u32 LE | timestamp f64 LE（毫秒）
/// 手柄帧（每帧 23 字节）：index u8 | buttons u16 | LX i16 | LY i16 | RX i16 | RY i16 | LT u16 | RT u16 |
///                       physicalPhysicality u32 LE (=1) | virtualPhysicality u32 BE (=1)
enum InputPacketEncoder {
    static let headerSize = 14
    static let gamepadFrameSize = 23
    static let metadataFrameSize = 28

    /// 连接后首先发送的客户端元数据报文（15 字节）
    static func clientMetadata(sequence: UInt32 = 0, timestampMs: Double, maxTouchpoints: UInt8 = 1) -> Data {
        var w = ByteWriter(capacity: 15)
        w.u16(InputReportType.clientMetadata.rawValue)
        w.u32(sequence)
        w.f64(timestampMs)
        w.u8(maxTouchpoints)
        return w.data
    }

    /// 常规输入报文：可同时携带视频元数据和手柄帧
    static func inputReport(sequence: UInt32,
                            timestampMs: Double,
                            metadata: [VideoMetadataFrame],
                            gamepads: [GamepadFrame]) -> Data {
        var type: InputReportType = []
        if !metadata.isEmpty { type.insert(.metadata) }
        if !gamepads.isEmpty { type.insert(.gamepad) }

        var size = headerSize
        if !metadata.isEmpty { size += 1 + metadataFrameSize * metadata.count }
        if !gamepads.isEmpty { size += 1 + gamepadFrameSize * gamepads.count }

        var w = ByteWriter(capacity: size)
        w.u16(type.rawValue)
        w.u32(sequence)
        w.f64(timestampMs)

        if !metadata.isEmpty {
            w.u8(UInt8(clamping: metadata.count))
            for m in metadata {
                w.u32(m.serverDataKey)
                w.u32(m.firstFramePacketArrivalTimeMs)
                w.u32(m.frameSubmittedTimeMs)
                w.u32(m.frameDecodedTimeMs)
                w.u32(m.frameRenderedTimeMs)
                w.u32(m.framePacketTimeMs)
                w.u32(m.frameDateNowMs)
            }
        }

        if !gamepads.isEmpty {
            w.u8(UInt8(clamping: gamepads.count))
            for frame in gamepads {
                let s = frame.state
                w.u8(frame.index)
                w.u16(s.buttons.rawValue)
                w.i16(normalizeAxis(s.leftStick.x))
                w.i16(normalizeAxis(s.leftStick.y))
                w.i16(normalizeAxis(s.rightStick.x))
                w.i16(normalizeAxis(s.rightStick.y))
                w.u16(normalizeTrigger(s.leftTrigger))
                w.u16(normalizeTrigger(s.rightTrigger))
                w.u32(1)      // PhysicalPhysicality
                w.u32BE(1)    // VirtualPhysicality（参考实现用大端写入）
            }
        }
        return w.data
    }

    /// -1...1 → -32767...32767（截断取整）
    static func normalizeAxis(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        let scaled = Double(value) * 32767
        if scaled >= 32767 { return 32767 }
        if scaled <= -32767 { return -32767 }
        return Int16(scaled.rounded(.towardZero))
    }

    /// 0...1 → 0...65535
    static func normalizeTrigger(_ value: Float) -> UInt16 {
        guard value.isFinite, value > 0 else { return 0 }
        let scaled = Double(value) * 65535
        if scaled >= 65535 { return 65535 }
        return UInt16(scaled.rounded(.towardZero))
    }
}

/// 服务器发来的震动报文
struct VibrationReport: Equatable {
    var gamepadIndex: UInt8
    var leftMotor: Float        // 0...1
    var rightMotor: Float
    var leftTriggerMotor: Float
    var rightTriggerMotor: Float
    var durationMs: UInt16
    var delayMs: UInt16
    var repeatCount: UInt8

    /// 字节布局：[0] reportType 低字节 (=128) [2] rumbleType [3] gamepadIndex
    /// [4..7] 四个马达百分比 [8..9] duration LE [10..11] delay LE [12] repeat
    static func parse(_ data: Data) -> VibrationReport? {
        let bytes = [UInt8](data)
        guard bytes.count >= 13, bytes[0] == UInt8(InputReportType.vibration.rawValue) else { return nil }
        func pct(_ i: Int) -> Float { min(1, Float(bytes[i]) / 100) }
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8) }
        return VibrationReport(
            gamepadIndex: bytes[3],
            leftMotor: pct(4),
            rightMotor: pct(5),
            leftTriggerMotor: pct(6),
            rightTriggerMotor: pct(7),
            durationMs: u16(8),
            delayMs: u16(10),
            repeatCount: bytes[12]
        )
    }
}

/// 服务器元数据报文：视频分辨率
struct ServerMetadataReport: Equatable {
    var height: UInt32
    var width: UInt32

    static func parse(_ data: Data) -> ServerMetadataReport? {
        let bytes = [UInt8](data)
        guard bytes.count >= 10, bytes[0] == UInt8(InputReportType.serverMetadata.rawValue) else { return nil }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
        }
        return ServerMetadataReport(height: u32(2), width: u32(6))
    }
}
