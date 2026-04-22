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
        gb == 0 ? "Unlimited" : "\(gb) GB"
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
                    title: "Global Unlimited",
                    description: "Best for heavy usage, streaming, and never worrying about data limits."
                ),
                DataPackOption(
                    id: "chatforia_esim_global_3",
                    product: "chatforia_esim_global_3",
                    scope: .global,
                    gb: 3,
                    title: "Global 3 GB",
                    description: "Great for short trips and light international use."
                ),
                DataPackOption(
                    id: "chatforia_esim_global_5",
                    product: "chatforia_esim_global_5",
                    scope: .global,
                    gb: 5,
                    title: "Global 5 GB",
                    description: "Perfect for moderate travel and daily connectivity."
                ),
                DataPackOption(
                    id: "chatforia_esim_global_10",
                    product: "chatforia_esim_global_10",
                    scope: .global,
                    gb: 10, // ✅ FIXED
                    title: "Global 10 GB",
                    description: "Ideal for longer trips, streaming, and frequent use."
                ),
            ]

        case .europe:
            return [
                DataPackOption(
                    id: "chatforia_esim_europe_unlimited",
                    product: "chatforia_esim_europe_unlimited",
                    scope: .europe,
                    gb: 0,
                    title: "Europe Unlimited",
                    description: "Best for heavy usage, streaming, and never worrying about data limits."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_3",
                    product: "chatforia_esim_europe_3",
                    scope: .europe,
                    gb: 3,
                    title: "Europe 3 GB",
                    description: "Great for quick trips, maps, and messaging."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_5",
                    product: "chatforia_esim_europe_5",
                    scope: .europe,
                    gb: 5,
                    title: "Europe 5 GB",
                    description: "Perfect for weekend trips and regular daily use."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_10",
                    product: "chatforia_esim_europe_10",
                    scope: .europe,
                    gb: 10,
                    title: "Europe 10 GB",
                    description: "Ideal for longer stays, streaming, and daily use."
                ),
                DataPackOption(
                    id: "chatforia_esim_europe_20",
                    product: "chatforia_esim_europe_20",
                    scope: .europe,
                    gb: 20,
                    title: "Europe 20 GB",
                    description: "Best for power users, hotspot use, and heavy browsing."
                ),
            ]

        case .local:
            return [
                DataPackOption(
                    id: "chatforia_esim_local_unlimited",
                    product: "chatforia_esim_local_unlimited",
                    scope: .local,
                    gb: 0,
                    title: "Local Unlimited",
                    description: "Best for heavy usage, streaming, and never worrying about data limits."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_3",
                    product: "chatforia_esim_local_3",
                    scope: .local,
                    gb: 3,
                    title: "Local 3 GB",
                    description: "Great for light use, maps, and messaging."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_5",
                    product: "chatforia_esim_local_5",
                    scope: .local,
                    gb: 5,
                    title: "Local 5 GB",
                    description: "Perfect for everyday use and regular browsing."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_10",
                    product: "chatforia_esim_local_10",
                    scope: .local,
                    gb: 10,
                    title: "Local 10 GB",
                    description: "Ideal for streaming, sharing, and heavier daily use."
                ),
                DataPackOption(
                    id: "chatforia_esim_local_20",
                    product: "chatforia_esim_local_20",
                    scope: .local,
                    gb: 20,
                    title: "Local 20 GB",
                    description: "Best for power users, hotspot, and high data usage."
                ),
            ]
        }
    }
}
