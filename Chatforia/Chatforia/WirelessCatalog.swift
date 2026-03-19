import Foundation

enum EsimScope: String, CaseIterable, Identifiable {
    case local
    case europe
    case global

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .europe: return "Europe"
        case .global: return "Global"
        }
    }

    var subtitle: String {
        switch self {
        case .local:
            return "Coverage for your current country or nearby local use."
        case .europe:
            return "Regional coverage across Europe."
        case .global:
            return "Broader international coverage for travel."
        }
    }
}

struct DataPackOption: Identifiable, Hashable {
    let id: String
    let product: String
    let scope: EsimScope
    let gb: Int
    let title: String
    let description: String

    var displayDataAmount: String {
        "\(gb) GB"
    }
}

enum WirelessCatalog {
    static func packs(for scope: EsimScope) -> [DataPackOption] {
        switch scope {
        case .global:
            return [
                DataPackOption(
                    id: "chatforia_esim_global_3",
                    product: "chatforia_esim_global_3",
                    scope: .global,
                    gb: 3,
                    title: "Global 3 GB",
                    description: "Global coverage for light travel."
                ),
                DataPackOption(
                    id: "chatforia_esim_global_5",
                    product: "chatforia_esim_global_5",
                    scope: .global,
                    gb: 5,
                    title: "Global 5 GB",
                    description: "Global coverage for moderate travel."
                )
            ]

        case .europe:
            return [
                DataPackOption(
                    id: "chatforia_esim_europe_3",
                    product: "chatforia_esim_europe_3",
                    scope: .europe,
                    gb: 3,
                    title: "Europe 3 GB",
                    description: "Great for quick trips and light use."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_5",
                    product: "chatforia_esim_europe_5",
                    scope: .europe,
                    gb: 5,
                    title: "Europe 5 GB",
                    description: "Weekend trips, maps, and regular messaging."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_10",
                    product: "chatforia_esim_europe_10",
                    scope: .europe,
                    gb: 10,
                    title: "Europe 10 GB",
                    description: "Longer stays and heavier usage."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_20",
                    product: "chatforia_esim_europe_20",
                    scope: .europe,
                    gb: 20,
                    title: "Europe 20 GB",
                    description: "Power travelers and hotspot use."
                )
            ]

        case .local:
            return [
                DataPackOption(
                    id: "chatforia_esim_local_3",
                    product: "chatforia_esim_local_3",
                    scope: .local,
                    gb: 3,
                    title: "Local 3 GB",
                    description: "Light use and short coverage needs."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_5",
                    product: "chatforia_esim_local_5",
                    scope: .local,
                    gb: 5,
                    title: "Local 5 GB",
                    description: "Regular daily usage."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_10",
                    product: "chatforia_esim_local_10",
                    scope: .local,
                    gb: 10,
                    title: "Local 10 GB",
                    description: "Heavy usage and media sharing."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_20",
                    product: "chatforia_esim_local_20",
                    scope: .local,
                    gb: 20,
                    title: "Local 20 GB",
                    description: "Power users and hotspot scenarios."
                )
            ]
        }
    }
}
