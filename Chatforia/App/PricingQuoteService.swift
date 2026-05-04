import Foundation

struct PricingQuote: Decodable, Hashable {
    let product: String?
    let country: String?
    let regionTier: String?
    let currency: String?
    let unitAmount: Int?
    let stripePriceId: String?
    let appleSku: String?
    let googleSku: String?
    let display: PricingQuoteDisplay?

    struct PricingQuoteDisplay: Decodable, Hashable {
        let amount: String?
        let currency: String?
    }
}

enum PricingProduct: String, CaseIterable {
    case plus = "chatforia_plus"
    case premiumMonthly = "chatforia_premium_monthly"
    case premiumAnnual = "chatforia_premium_annual"

    case esimLocal3 = "chatforia_esim_local_3"
    case esimLocal5 = "chatforia_esim_local_5"
    case esimLocal10 = "chatforia_esim_local_10"
    case esimLocal20 = "chatforia_esim_local_20"

    case esimEurope3 = "chatforia_esim_europe_3"
    case esimEurope5 = "chatforia_esim_europe_5"
    case esimEurope10 = "chatforia_esim_europe_10"
    case esimEurope20 = "chatforia_esim_europe_20"

    case esimGlobal3 = "chatforia_esim_global_3"
    case esimGlobal5 = "chatforia_esim_global_5"
    case esimGlobal10 = "chatforia_esim_global_10"
    
    case esimLocalUnlimited = "chatforia_esim_local_unlimited"
    case esimEuropeUnlimited = "chatforia_esim_europe_unlimited"
    case esimGlobalUnlimited = "chatforia_esim_global_unlimited"
}

enum PricingQuoteServiceError: Error {
    case invalidResponse
}

final class PricingQuoteService {
    static let shared = PricingQuoteService()
    private init() {}

    private let fallbackQuotes: [PricingProduct: (currency: String, unitAmount: Int)] = [
        .plus: ("USD", 499),
        .premiumMonthly: ("USD", 2499),
        .premiumAnnual: ("USD", 22500),

        .esimLocalUnlimited: ("USD", 5999),
        .esimLocal3: ("USD", 1499),
        .esimLocal5: ("USD", 2299),
        .esimLocal10: ("USD", 3499),
        .esimLocal20: ("USD", 5499),

        .esimEuropeUnlimited: ("USD", 6999),
        .esimEurope3: ("USD", 1699),
        .esimEurope5: ("USD", 2499),
        .esimEurope10: ("USD", 3699),
        .esimEurope20: ("USD", 6499),

        .esimGlobalUnlimited: ("USD", 7999),
        .esimGlobal3: ("USD", 2199),
        .esimGlobal5: ("USD", 3299),
        .esimGlobal10: ("USD", 4999),
    ]

    func getQuote(
        product: PricingProduct,
        country: String? = nil,
        currency: String? = nil,
        token: String? = nil
    ) async -> PricingQuote? {
        let queryItems = buildQueryItems(
            product: product.rawValue,
            country: country,
            currency: currency
        )

        let path = "pricing/quote?\(queryItems)"
        let request = APIRequest(
            path: path,
            method: .GET,
            body: nil,
            requiresAuth: false
        )

        do {
            let quote: PricingQuote = try await APIClient.shared.send(request, token: token)
            return normalizedQuote(quote, for: product, country: country)
        } catch {
            return fallbackQuote(for: product, country: country, currency: currency)
        }
    }

    func getQuotes(
        products: [PricingProduct],
        country: String? = nil,
        currency: String? = nil,
        token: String? = nil
    ) async -> [PricingProduct: PricingQuote] {
        var results: [PricingProduct: PricingQuote] = [:]

        await withTaskGroup(of: (PricingProduct, PricingQuote?).self) { group in
            for product in products {
                group.addTask {
                    let quote = await self.getQuote(
                        product: product,
                        country: country,
                        currency: currency,
                        token: token
                    )
                    return (product, quote)
                }
            }

            for await (product, quote) in group {
                if let quote {
                    results[product] = quote
                }
            }
        }

        return results
    }

    func formattedPrice(
        for quote: PricingQuote?,
        fallbackProduct: PricingProduct? = nil,
        locale: Locale = .current
    ) -> String? {
        if let quote,
           let currency = quote.currency,
           let unitAmount = quote.unitAmount {
            return formatMoney(unitAmount: unitAmount, currency: currency, locale: locale)
        }

        if let fallbackProduct,
           let fallback = fallbackQuotes[fallbackProduct] {
            return formatMoney(
                unitAmount: fallback.unitAmount,
                currency: fallback.currency,
                locale: locale
            )
        }

        return nil
    }

    private func buildQueryItems(product: String, country: String?, currency: String?) -> String {
        var parts: [String] = []

        if let productEncoded = product.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("product=\(productEncoded)")
        }

        if let country,
           let encoded = country.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("country=\(encoded)")
        }

        if let currency,
           let encoded = currency.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("currency=\(encoded)")
        }

        return parts.joined(separator: "&")
    }

    private func normalizedQuote(
        _ quote: PricingQuote,
        for product: PricingProduct,
        country: String?
    ) -> PricingQuote {
        PricingQuote(
            product: quote.product ?? product.rawValue,
            country: quote.country ?? country ?? "US",
            regionTier: quote.regionTier,
            currency: quote.currency,
            unitAmount: quote.unitAmount,
            stripePriceId: quote.stripePriceId,
            appleSku: quote.appleSku,
            googleSku: quote.googleSku,
            display: quote.display
        )
    }

    private func fallbackQuote(
        for product: PricingProduct,
        country: String?,
        currency: String?
    ) -> PricingQuote? {
        guard let fallback = fallbackQuotes[product] else { return nil }

        let resolvedCurrency = (currency ?? fallback.currency).uppercased()

        return PricingQuote(
            product: product.rawValue,
            country: country ?? "US",
            regionTier: "ROW",
            currency: resolvedCurrency,
            unitAmount: fallback.unitAmount,
            stripePriceId: nil,
            appleSku: nil,
            googleSku: nil,
            display: .init(
                amount: nil,
                currency: resolvedCurrency
            )
        )
    }

    private func formatMoney(unitAmount: Int, currency: String, locale: Locale) -> String {
        let zeroDecimalCurrencies: Set<String> = [
            "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "PYG",
            "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
        ]

        let threeDecimalCurrencies: Set<String> = ["BHD", "JOD", "KWD", "OMR", "TND"]

        let normalizedCurrency = currency.uppercased()

        let divisor: Double
        let fractionDigits: Int

        if zeroDecimalCurrencies.contains(normalizedCurrency) {
            divisor = 1
            fractionDigits = 0
        } else if threeDecimalCurrencies.contains(normalizedCurrency) {
            divisor = 1000
            fractionDigits = 3
        } else {
            divisor = 100
            fractionDigits = 2
        }

        let amount = Double(unitAmount) / divisor

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = normalizedCurrency
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits

        return formatter.string(from: NSNumber(value: amount))
            ?? "\(amount) \(normalizedCurrency)"
    }
}
