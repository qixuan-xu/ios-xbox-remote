import XCTest
import CryptoKit
@testable import XboxRemote

final class ProtocolToolsTests: XCTestCase {

    // MARK: Teredo

    func testTeredoDecoding() {
        // 经典示例：2001:0:4136:e378:8000:63bf:3fff:fdd2 → 192.0.2.45:40000
        let t = TeredoAddress("2001:0:4136:e378:8000:63bf:3fff:fdd2")
        XCTAssertEqual(t?.ipv4, "192.0.2.45")
        XCTAssertEqual(t?.port, 40000)
        XCTAssertNil(TeredoAddress("fe80::1"))
    }

    func testTeredoCandidateExpansion() {
        let c = GssvClient.IceCandidateDTO(candidate: "a=candidate:1 1 UDP 100 2001:0:4136:e378:8000:63bf:3fff:fdd2 1234 typ host",
                                           sdpMid: "0", sdpMLineIndex: 0)
        let end = GssvClient.IceCandidateDTO(candidate: "a=end-of-candidates", sdpMid: "0", sdpMLineIndex: 0)
        let out = TeredoAddress.expand([c, end])
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out[0].candidate.contains("192.0.2.45 9002"))
        XCTAssertTrue(out[1].candidate.contains("192.0.2.45 40000"))
        XCTAssertEqual(out[2], c)
    }

    func testParseRemoteCandidatesTolerant() {
        let raw = #"[{"candidate":"a=candidate:1 1 UDP 100 10.0.0.5 9002 typ host","sdpMid":"0","sdpMLineIndex":"0"},{"candidate":"a=end-of-candidates","sdpMLineIndex":0}]"#
        let list = GssvClient.parseCandidates(raw)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].sdpMLineIndex, 0)
        XCTAssertEqual(list[0].sdpMid, "0")
    }

    func testLanCandidatesFirstAndNoTeredoExpansion() {
        // 用户日志里真实的一组远端候选
        let raw = #"[{"candidate":"candidate:3454249326 1 udp 2122194687 172.16.32.82 9002 typ host generation 0","sdpMLineIndex":0,"sdpMid":"0"},{"candidate":"candidate:11766519 1 udp 2122255103 2001::14c9:c84e:c7a:61b2:bd42:9d1d 9002 typ host generation 0","sdpMLineIndex":0,"sdpMid":"0"},{"candidate":"candidate:1655261264 1 udp 1685987071 66.189.98.226 9002 typ srflx raddr 172.16.32.82 rport 9002","sdpMLineIndex":0,"sdpMid":"0"},{"candidate":"a=candidate:1 1 UDP 100 172.16.32.82 9002 typ host ","sdpMLineIndex":0,"sdpMid":"0"},{"candidate":"a=end-of-candidates","sdpMLineIndex":0,"sdpMid":"0"}]"#
        let ordered = IcePreference.reorder(GssvClient.parseCandidates(raw))
        XCTAssertEqual(ordered.count, 4)
        XCTAssertTrue(ordered[0].candidate.contains("172.16.32.82"))
        XCTAssertTrue(ordered[1].candidate.contains("172.16.32.82"))
        XCTAssertFalse(ordered.contains { $0.candidate.contains("candidate:10 ") || $0.candidate.contains("candidate:11 ") })
    }

    func testRouteClassification() {
        XCTAssertEqual(StreamRoute.classify(remoteAddress: "172.16.32.82", candidateType: "host"), .lan)
        XCTAssertEqual(StreamRoute.classify(remoteAddress: "192.168.1.5", candidateType: "host"), .lan)
        XCTAssertEqual(StreamRoute.classify(remoteAddress: "66.189.98.226", candidateType: "srflx"), .publicIP)
        XCTAssertEqual(StreamRoute.classify(remoteAddress: "2001:0:14c9::1", candidateType: "host"), .teredo)
        XCTAssertEqual(StreamRoute.classify(remoteAddress: "1.2.3.4", candidateType: "relay"), .relay)
        XCTAssertFalse(IcePreference.isPrivateIPv4("172.32.0.1"))
    }

    // MARK: SDP

    func testPreferH264Ordering() {
        let sdp = [
            "v=0",
            "m=audio 9 UDP/TLS/RTP/SAVPF 111",
            "a=rtpmap:111 opus/48000/2",
            "m=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103 127",
            "a=rtpmap:96 VP8/90000",
            "a=rtpmap:97 rtx/90000",
            "a=fmtp:97 apt=96",
            "a=rtpmap:102 H264/90000",
            "a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f",
            "a=rtpmap:103 H264/90000",
            "a=fmtp:103 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f",
            "a=rtpmap:127 red/90000",
            ""
        ].joined(separator: "\r\n")
        let out = SdpTools.preferH264(sdp)
        XCTAssertTrue(out.contains("m=video 9 UDP/TLS/RTP/SAVPF 103 102 96 97 127"), out)
        XCTAssertTrue(out.contains("m=audio 9 UDP/TLS/RTP/SAVPF 111"))
    }

    func testSetBitrate() {
        let sdp = "v=0\r\nm=video 9 UDP 96\r\nc=IN IP4 0.0.0.0\r\na=rtpmap:96 H264/90000\r\n"
        let out = SdpTools.setBitrate(sdp, media: "video", kbps: 12000)
        XCTAssertTrue(out.contains("c=IN IP4 0.0.0.0\r\nb=AS:12000\r\na=rtpmap"), out)
    }

    // MARK: 签名

    func testSigningPayloadLayout() {
        let payload = RequestSigner.signingPayload(path: "/a", authorizationToken: "", body: Data("{}".utf8), timestamp: 1)
        var expected: [UInt8] = [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]
        expected.append(contentsOf: Array("POST".utf8))
        expected.append(0)
        expected.append(contentsOf: Array("/a".utf8))
        expected.append(contentsOf: [0, 0])
        expected.append(contentsOf: Array("{}".utf8))
        expected.append(0)
        XCTAssertEqual([UInt8](payload), expected)
    }

    func testWindowsTimestamp() {
        XCTAssertEqual(RequestSigner.windowsTimestamp(for: Date(timeIntervalSince1970: 0)), 116_444_736_000_000_000)
    }

    func testSignatureVerifies() throws {
        let key = P256.Signing.PrivateKey()
        let signer = RequestSigner(privateKey: key)
        let url = URL(string: "https://device.auth.xboxlive.com/device/authenticate")!
        let body = Data(#"{"hello":"world"}"#.utf8)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let header = try XCTUnwrap(Data(base64Encoded: try signer.signatureHeader(url: url, body: body, date: date)))
        XCTAssertEqual(header.count, 12 + 64)
        XCTAssertEqual([UInt8](header.prefix(4)), [0, 0, 0, 1])

        let ts = header[4..<12].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        XCTAssertEqual(ts, RequestSigner.windowsTimestamp(for: date))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: header.suffix(64))
        let payload = RequestSigner.signingPayload(path: "/device/authenticate", authorizationToken: "", body: body, timestamp: ts)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: payload))

        let jwk = signer.proofKey
        XCTAssertEqual(jwk["crv"], "P-256")
        XCTAssertEqual(Data(base64URLEncoded: jwk["x"] ?? "")?.count, 32)
    }

    func testXboxDateParsing() {
        let d = XboxDate.parse("2024-05-01T12:34:56.1234567Z")
        XCTAssertEqual(d?.timeIntervalSince1970, 1_714_566_896)
        XCTAssertNotNil(XboxDate.parse("2024-05-01T12:34:56Z"))
    }

    func testFormEncoding() {
        XCTAssertEqual(FormEncoding.encode(["b": "x y", "a": "s::t/u"]), "a=s%3A%3At%2Fu&b=x%20y")
    }

    // MARK: 键位

    func testKeyboardMapping() {
        let bindings = KeyBindings.default
        let s = KeyboardMapper.state(pressed: [.key("w"), .key("d"), .key("space"), .mouseLeft], bindings: bindings)
        XCTAssertTrue(s.buttons.contains(.a))
        XCTAssertEqual(s.rightTrigger, 1)
        XCTAssertEqual(s.leftStick.magnitude, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(s.leftStick.x, 0)
        XCTAssertGreaterThan(s.leftStick.y, 0)

        let opposite = KeyboardMapper.state(pressed: [.key("a"), .key("d")], bindings: bindings)
        XCTAssertEqual(opposite.leftStick, .zero)
    }

    func testKeyBindingSwap() {
        var bindings = KeyBindings.default
        // 把 F（原本是 X）绑给 A：A 的原主键 Space 应交换给 X
        let swapped = bindings.bind(.key("f"), to: .a)
        XCTAssertEqual(swapped, .x)
        XCTAssertEqual(bindings.inputs(for: .a).first, .key("f"))
        XCTAssertEqual(bindings.inputs(for: .x).first, .key("space"))

        let data = try? JSONEncoder().encode(bindings)
        let decoded = data.flatMap { try? JSONDecoder().decode(KeyBindings.self, from: $0) }
        XCTAssertEqual(decoded, bindings)
    }
}
