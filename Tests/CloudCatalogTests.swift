import XCTest
@testable import XboxRemote

final class CloudCatalogTests: XCTestCase {

    func testImageURLAddsScheme() {
        XCTAssertEqual(CatalogClient.imageURL("//store-images.s-microsoft.com/image/abc")?.absoluteString,
                       "https://store-images.s-microsoft.com/image/abc")
        XCTAssertNil(CatalogClient.imageURL(""))
        XCTAssertNil(CatalogClient.imageURL(nil))
    }

    func testMergeTitlesWithCatalog() throws {
        let titlesJSON = """
        {"results":[
          {"titleId":"HALO","details":{"productId":"9P1","hasEntitlement":true}},
          {"titleId":"NOCATALOG","details":{"productId":"9P2"}},
          {"titleId":"NOPRODUCT"}
        ]}
        """
        let catalogJSON = """
        {"Products":{"9P1":{"ProductTitle":"Halo","PublisherName":"Xbox Game Studios",
          "Image_Tile":{"URL":"//img/tile"},"Image_Poster":{"URL":"//img/poster"}}}}
        """
        let items = try JSONDecoder().decode(GssvClient.TitlesResponse.self, from: Data(titlesJSON.utf8)).results
        struct Wrapper: Decodable { var Products: [String: CatalogClient.Product] }
        let products = try JSONDecoder().decode(Wrapper.self, from: Data(catalogJSON.utf8)).Products

        let merged = CatalogClient.merge(items, products: products)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, "HALO")
        XCTAssertEqual(merged[0].name, "Halo")
        XCTAssertEqual(merged[0].posterURL?.absoluteString, "https://img/poster")
    }
}
