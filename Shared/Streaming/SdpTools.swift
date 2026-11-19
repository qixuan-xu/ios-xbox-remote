import Foundation

/// SDP 文本处理（纯函数，可单元测试）
enum SdpTools {

    /// 把视频编解码器顺序调整为：H.264 Main(4d) > H.264 Constrained Baseline(42e0) > H.264 Baseline(420) > 其他。
    /// 等价于浏览器里的 setCodecPreferences，参考实现 lib/sdp.ts 的 getDefaultCodecPreferences。
    static func preferH264(_ sdp: String) -> String {
        var lines = sdp.components(separatedBy: "\r\n")
        if lines.count <= 1 { lines = sdp.components(separatedBy: "\n") }
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"

        guard let mIndex = lines.firstIndex(where: { $0.hasPrefix("m=video") }) else { return sdp }
        let sectionEnd = lines[(mIndex + 1)...].firstIndex(where: { $0.hasPrefix("m=") }) ?? lines.count

        // payload type -> 编解码器名 / fmtp
        var codecName: [String: String] = [:]
        var fmtp: [String: String] = [:]
        for line in lines[mIndex..<sectionEnd] {
            if line.hasPrefix("a=rtpmap:") {
                let rest = line.dropFirst("a=rtpmap:".count)
                let parts = rest.split(separator: " ", maxSplits: 1)
                if parts.count == 2 { codecName[String(parts[0])] = String(parts[1]).lowercased() }
            } else if line.hasPrefix("a=fmtp:") {
                let rest = line.dropFirst("a=fmtp:".count)
                let parts = rest.split(separator: " ", maxSplits: 1)
                if parts.count == 2 { fmtp[String(parts[0])] = String(parts[1]).lowercased() }
            }
        }

        var mParts = lines[mIndex].split(separator: " ").map(String.init)
        guard mParts.count > 3 else { return sdp }
        let header = Array(mParts[0..<3])
        let payloads = Array(mParts[3...])

        func rank(_ pt: String) -> Int {
            let name = codecName[pt] ?? ""
            let params = fmtp[pt] ?? ""
            if name.hasPrefix("h264") {
                if params.contains("profile-level-id=4d") { return 0 }
                if params.contains("profile-level-id=42e") { return 1 }
                if params.contains("profile-level-id=420") { return 2 }
                return 3
            }
            if name.hasPrefix("rtx") {
                // rtx 跟随其关联的编码
                if let apt = params.components(separatedBy: ";").first(where: { $0.hasPrefix("apt=") })?.dropFirst(4) {
                    return rank(String(apt)) + 10
                }
                return 50
            }
            if name.hasPrefix("ulpfec") || name.hasPrefix("flexfec") || name.hasPrefix("red") { return 40 }
            return 30
        }

        let sorted = payloads.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
        mParts = header + sorted
        lines[mIndex] = mParts.joined(separator: " ")
        return lines.joined(separator: separator)
    }

    /// 在指定媒体段加上 b=AS 码率上限（kbps）
    static func setBitrate(_ sdp: String, media: String, kbps: Int) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        guard var i = lines.firstIndex(where: { $0.hasPrefix("m=\(media)") }) else { return sdp }
        i += 1
        while i < lines.count, lines[i].hasPrefix("i=") || lines[i].hasPrefix("c=") { i += 1 }
        if i < lines.count, lines[i].hasPrefix("b=") {
            lines[i] = "b=AS:\(kbps)"
        } else {
            lines.insert("b=AS:\(kbps)", at: i)
        }
        return lines.joined(separator: separator)
    }

    /// 开启立体声
    static func enableStereo(_ sdp: String) -> String {
        sdp.replacingOccurrences(of: "useinbandfec=1", with: "useinbandfec=1;stereo=1")
    }
}

/// Teredo IPv6 地址解析：xHome 返回的 2001: 开头的候选需要额外转换成 IPv4 候选。
/// 对照参考实现 lib/teredo.ts / lib/ice.ts。
struct TeredoAddress: Equatable {
    var ipv4: String
    var port: Int

    init?(_ address: String) {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 8, parts[0].lowercased() == "2001" else { return nil }
        func pad(_ s: String) -> String { String(repeating: "0", count: max(0, 4 - s.count)) + s }
        let ipHex = pad(parts[6]) + pad(parts[7])
        let portHex = pad(parts[5])
        guard ipHex.count == 8 else { return nil }
        var octets: [Int] = []
        var idx = ipHex.startIndex
        for _ in 0..<4 {
            let next = ipHex.index(idx, offsetBy: 2)
            guard let v = Int(ipHex[idx..<next], radix: 16) else { return nil }
            octets.append(~v & 0xFF)
            idx = next
        }
        guard let p = Int(portHex, radix: 16) else { return nil }
        ipv4 = octets.map(String.init).joined(separator: ".")
        port = ~p & 0xFFFF
    }

    /// 把远端候选展开：对 Teredo 地址额外生成两个 IPv4 host 候选
    static func expand(_ candidates: [GssvClient.IceCandidateDTO]) -> [GssvClient.IceCandidateDTO] {
        var out: [GssvClient.IceCandidateDTO] = []
        for c in candidates {
            if c.candidate == "a=end-of-candidates" { continue }
            let fields = c.candidate.split(separator: " ").map(String.init)
            if fields.count > 4, let teredo = TeredoAddress(fields[4]) {
                out.append(.init(candidate: "a=candidate:10 1 UDP 1 \(teredo.ipv4) 9002 typ host ",
                                 sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex))
                out.append(.init(candidate: "a=candidate:11 1 UDP 1 \(teredo.ipv4) \(teredo.port) typ host ",
                                 sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex))
            }
            out.append(c)
        }
        return out
    }
}

/// 远端候选的添加顺序：同一局域网时优先直连
enum IcePreference {
    static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        return false
    }

    static func address(of candidate: String) -> String? {
        let fields = candidate.split(separator: " ").map(String.init)
        return fields.count > 4 ? fields[4] : nil
    }

    /// 有私有 IPv4 地址的候选时：先加局域网候选，再加其他；不再从 Teredo 地址换算出公网 IPv4 候选
    /// （同一局域网下那些候选只会把连接引向公网回流）。没有局域网候选时沿用 Teredo 展开。
    static func reorder(_ candidates: [GssvClient.IceCandidateDTO]) -> [GssvClient.IceCandidateDTO] {
        let real = candidates.filter { $0.candidate != "a=end-of-candidates" }
        let lan = real.filter { c in address(of: c.candidate).map(isPrivateIPv4) ?? false }
        guard !lan.isEmpty else { return TeredoAddress.expand(candidates) }
        let others = real.filter { c in !(address(of: c.candidate).map(isPrivateIPv4) ?? false) }
        return lan + others
    }
}
