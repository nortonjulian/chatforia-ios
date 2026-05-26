import Foundation

enum EsimScope: String, CaseIterable, Identifiable {
    case local
    case europe
    case global

    var id: String { rawValue }

    func displayName(languageCode: String) -> String {
        switch self {
        case .local:
            return appText("esim.local", languageCode: languageCode)

        case .europe:
            return appText("esim.europe", languageCode: languageCode)

        case .global:
            return appText("esim.global", languageCode: languageCode)
        }
    }

    func subtitle(languageCode: String) -> String {
        switch self {
        case .local:
            return appText("esim.localSubtitle", languageCode: languageCode)

        case .europe:
            return appText("esim.europeSubtitle", languageCode: languageCode)

        case .global:
            return appText("esim.globalSubtitle", languageCode: languageCode)
        }
    }
}

struct DataPackOption: Identifiable, Hashable {
    let id: String
    let product: String
    let scope: EsimScope
    let gb: Int
    let titleKey: String
    let descriptionKey: String

    func title(languageCode: String) -> String {
        appText(titleKey, languageCode: languageCode)
    }

    func description(languageCode: String) -> String {
        appText(descriptionKey, languageCode: languageCode)
    }

    func displayDataAmount(languageCode: String) -> String {
        gb == 0
            ? appText("esim.unlimited", languageCode: languageCode)
            : "\(gb) GB"
    }
}

enum WirelessCatalog {
    static func packs(for scope: EsimScope) -> [DataPackOption] {
        switch scope {
        case .global:
            return [
                DataPackOption(
                    id: "chatforia_esim_global_unlimited",
                    product: "chatforia_esim_global_unlimited",
                    scope: .global,
                    gb: 0,
                    titleKey: "esim.globalUnlimited",
                    descriptionKey: "esim.heavyUsageDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_global_3",
                    product: "chatforia_esim_global_3",
                    scope: .global,
                    gb: 3,
                    titleKey: "esim.global3gb",
                    descriptionKey: "esim.global3gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_global_5",
                    product: "chatforia_esim_global_5",
                    scope: .global,
                    gb: 5,
                    titleKey: "esim.global5gb",
                    descriptionKey: "esim.global5gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_global_10",
                    product: "chatforia_esim_global_10",
                    scope: .global,
                    gb: 10,
                    titleKey: "esim.global10gb",
                    descriptionKey: "esim.global10gbDescription"
                )
            ]

        case .europe:
            return [
                DataPackOption(
                    id: "chatforia_esim_europe_unlimited",
                    product: "chatforia_esim_europe_unlimited",
                    scope: .europe,
                    gb: 0,
                    titleKey: "esim.europeUnlimited",
                    descriptionKey: "esim.heavyUsageDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_3",
                    product: "chatforia_esim_europe_3",
                    scope: .europe,
                    gb: 3,
                    titleKey: "esim.europe3gb",
                    descriptionKey: "esim.europe3gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_5",
                    product: "chatforia_esim_europe_5",
                    scope: .europe,
                    gb: 5,
                    titleKey: "esim.europe5gb",
                    descriptionKey: "esim.europe5gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_10",
                    product: "chatforia_esim_europe_10",
                    scope: .europe,
                    gb: 10,
                    titleKey: "esim.europe10gb",
                    descriptionKey: "esim.europe10gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_20",
                    product: "chatforia_esim_europe_20",
                    scope: .europe,
                    gb: 20,
                    titleKey: "esim.europe20gb",
                    descriptionKey: "esim.europe20gbDescription"
                )
            ]

        case .local:
            return [
                DataPackOption(
                    id: "chatforia_esim_local_unlimited",
                    product: "chatforia_esim_local_unlimited",
                    scope: .local,
                    gb: 0,
                    titleKey: "esim.localUnlimited",
                    descriptionKey: "esim.heavyUsageDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_local_3",
                    product: "chatforia_esim_local_3",
                    scope: .local,
                    gb: 3,
                    titleKey: "esim.local3gb",
                    descriptionKey: "esim.local3gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_local_5",
                    product: "chatforia_esim_local_5",
                    scope: .local,
                    gb: 5,
                    titleKey: "esim.local5gb",
                    descriptionKey: "esim.local5gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_local_10",
                    product: "chatforia_esim_local_10",
                    scope: .local,
                    gb: 10,
                    titleKey: "esim.local10gb",
                    descriptionKey: "esim.local10gbDescription"
                ),
                DataPackOption(
                    id: "chatforia_esim_local_20",
                    product: "chatforia_esim_local_20",
                    scope: .local,
                    gb: 20,
                    titleKey: "esim.local20gb",
                    descriptionKey: "esim.local20gbDescription"
                )
            ]
        }
    }
}
