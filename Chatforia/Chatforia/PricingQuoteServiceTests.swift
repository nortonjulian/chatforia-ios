import XCTest
@testable import Chatforia

@MainActor
final class PricingQuoteServiceTests: XCTestCase {

    func testPricingQuoteDecodesFullResponse() throws {
        let json = """
        {
          "product": "chatforia_plus",
          "country": "US",
          "regionTier": "ROW",
          "currency": "USD",
          "unitAmount": 499,
          "stripePriceId": "price_123",
          "appleSku": "plus.monthly",
          "googleSku": "plus.monthly",
          "display": {
            "amount": "$4.99",
            "currency": "USD"
          }
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(PricingQuote.self, from: json)

        XCTAssertEqual(quote.product, "chatforia_plus")
        XCTAssertEqual(quote.country, "US")
        XCTAssertEqual(quote.regionTier, "ROW")
        XCTAssertEqual(quote.currency, "USD")
        XCTAssertEqual(quote.unitAmount, 499)
        XCTAssertEqual(quote.stripePriceId, "price_123")
        XCTAssertEqual(quote.appleSku, "plus.monthly")
        XCTAssertEqual(quote.googleSku, "plus.monthly")
        XCTAssertEqual(quote.display?.amount, "$4.99")
        XCTAssertEqual(quote.display?.currency, "USD")
    }

    func testFormattedPriceUsesQuoteAmountUSD() {
        let quote = PricingQuote(
            product: "chatforia_plus",
            country: "US",
            regionTier: "ROW",
            currency: "USD",
            unitAmount: 499,
            stripePriceId: nil,
            appleSku: nil,
            googleSku: nil,
            display: nil
        )

        let result = PricingQuoteService.shared.formattedPrice(
            for: quote,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(result, "$4.99")
    }

    func testFormattedPriceUsesFallbackProductWhenQuoteNil() {
        let result = PricingQuoteService.shared.formattedPrice(
            for: nil,
            fallbackProduct: .plus,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(result, "$4.99")
    }

    func testFormattedPriceSupportsZeroDecimalCurrency() {
        let quote = PricingQuote(
            product: "test",
            country: "JP",
            regionTier: "ROW",
            currency: "JPY",
            unitAmount: 500,
            stripePriceId: nil,
            appleSku: nil,
            googleSku: nil,
            display: nil
        )

        let result = PricingQuoteService.shared.formattedPrice(
            for: quote,
            locale: Locale(identifier: "ja_JP")
        )

        XCTAssertTrue(result?.contains("500") ?? false)
    }

    func testFormattedPriceSupportsThreeDecimalCurrency() {
        let quote = PricingQuote(
            product: "test",
            country: "KW",
            regionTier: "ROW",
            currency: "KWD",
            unitAmount: 1234,
            stripePriceId: nil,
            appleSku: nil,
            googleSku: nil,
            display: nil
        )

        let result = PricingQuoteService.shared.formattedPrice(
            for: quote,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(result?.contains("1.234") ?? false)
    }

    func testFormattedPriceReturnsNilWhenNoQuoteOrFallback() {
        let result = PricingQuoteService.shared.formattedPrice(
            for: nil,
            fallbackProduct: nil
        )

        XCTAssertNil(result)
    }

    func testPricingProductRawValues() {
        XCTAssertEqual(PricingProduct.plus.rawValue, "chatforia_plus")
        XCTAssertEqual(PricingProduct.premiumMonthly.rawValue, "chatforia_premium_monthly")
        XCTAssertEqual(PricingProduct.premiumAnnual.rawValue, "chatforia_premium_annual")
        XCTAssertEqual(PricingProduct.esimLocal3.rawValue, "chatforia_esim_local_3")
        XCTAssertEqual(PricingProduct.esimGlobalUnlimited.rawValue, "chatforia_esim_global_unlimited")
    }
}
