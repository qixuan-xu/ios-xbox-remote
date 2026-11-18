import Foundation

/// 云游戏里的一款游戏
struct CloudTitle: Identifiable, Hashable, Codable {
    var id: String              // xCloud titleId（开流时使用）
    var productId: String?
    var name: String
    var publisher: String?
    var tileURL: URL?           // 方形封面
    var posterURL: URL?         // 竖版海报
    var hasEntitlement: Bool = true

    static let demo: [CloudTitle] = [
        ("demo-1", "Starfall Odyssey", "Nebula Works"),
        ("demo-2", "Racing Horizon", "Apex Studios"),
        ("demo-3", "Shadow Tactics", "Ironclad"),
        ("demo-4", "Pixel Kingdoms", "Tiny Forge"),
        ("demo-5", "Deep Ocean", "Blue Lantern"),
        ("demo-6", "Neon Drift", "Synthwave Co."),
        ("demo-7", "Frontier Legends", "Northwind"),
        ("demo-8", "Puzzle Garden", "Calm Games")
    ].map { CloudTitle(id: $0.0, productId: nil, name: $0.1, publisher: $0.2, tileURL: nil, posterURL: nil) }
}

/// 云游戏可用状态
enum CloudAvailability: Equatable {
    case unknown
    case loading
    case available
    case unavailable(String)
}

extension GssvClient {
    struct TitlesResponse: Decodable {
        struct Item: Decodable {
            struct Details: Decodable {
                var productId: String?
                var hasEntitlement: Bool?
            }
            var titleId: String
            var details: Details?
        }
        var results: [Item]
    }

    /// 云游戏可玩的全部游戏（只有 titleId 和 productId，名字和封面要再查目录）
    func cloudTitles() async throws -> [TitlesResponse.Item] {
        let (data, _) = try await requestData("GET", "/v2/titles")
        return try JSONDecoder().decode(TitlesResponse.self, from: data).results
    }

    /// 最近玩过的云游戏
    func recentCloudTitles() async throws -> [TitlesResponse.Item] {
        let (data, _) = try await requestData("GET", "/v2/titles/mru?mr=25")
        return (try? JSONDecoder().decode(TitlesResponse.self, from: data).results) ?? []
    }
}

/// Game Pass 商店目录：用 productId 批量查名字和封面（与 Greenlight 相同的接口）
enum CatalogClient {
    struct Product: Decodable {
        struct Image: Decodable { var URL: String? }
        var ProductTitle: String?
        var PublisherName: String?
        var XCloudTitleId: String?
        var Image_Tile: Image?
        var Image_Poster: Image?
    }
    private struct Response: Decodable { var Products: [String: Product] }

    static func products(_ ids: [String], session: URLSession = .shared) async throws -> [String: Product] {
        let (market, language) = localeCodes()
        var result: [String: Product] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            var comps = URLComponents(string: "https://catalog.gamepass.com/v3/products")!
            comps.queryItems = [
                URLQueryItem(name: "market", value: market),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "hydration", value: "RemoteHighSapphire0")
            ]
            var request = URLRequest(url: comps.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("0", forHTTPHeaderField: "ms-cv")
            request.setValue("Xbox Cloud Gaming Web", forHTTPHeaderField: "calling-app-name")
            request.setValue("21.0.0", forHTTPHeaderField: "calling-app-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["Products": batch])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { continue }
            if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
                result.merge(decoded.Products) { a, _ in a }
            }
        }
        return result
    }

    /// 目录里的图片地址形如 //store-images.s-microsoft.com/...
    static func imageURL(_ raw: String?) -> URL? {
        guard var s = raw, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }

    static func localeCodes() -> (market: String, language: String) {
        let region = Locale.current.region?.identifier ?? "US"
        let lang = Locale.preferredLanguages.first ?? "en-US"
        return (region, lang)
    }

    /// 把 titles 接口和目录信息合并成界面用的模型
    static func merge(_ items: [GssvClient.TitlesResponse.Item], products: [String: Product]) -> [CloudTitle] {
        items.compactMap { item in
            let pid = item.details?.productId
            let product = pid.flatMap { products[$0] }
            guard let name = product?.ProductTitle, !name.isEmpty else { return nil }
            return CloudTitle(id: item.titleId,
                              productId: pid,
                              name: name,
                              publisher: product?.PublisherName,
                              tileURL: imageURL(product?.Image_Tile?.URL),
                              posterURL: imageURL(product?.Image_Poster?.URL),
                              hasEntitlement: item.details?.hasEntitlement ?? true)
        }
    }
}
