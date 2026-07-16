import Foundation
import Combine

@MainActor
final class CheckoutReturnCoordinator: ObservableObject {
    enum Destination: Equatable {
        case completed(sessionId: String)
        case canceled
    }

    struct Event: Identifiable, Equatable {
        let id: UUID
        let destination: Destination
    }

    @Published private(set) var pendingEvent: Event?
    @Published private(set) var isWirelessVisible = false

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let destination = Self.destination(for: url) else {
            return false
        }

        if pendingEvent?.destination == destination {
            return true
        }

        pendingEvent = Event(
            id: UUID(),
            destination: destination
        )

        return true
    }

    func consume(_ event: Event) {
        guard pendingEvent?.id == event.id else {
            return
        }

        pendingEvent = nil
    }

    func setWirelessVisible(_ isVisible: Bool) {
        isWirelessVisible = isVisible
    }

    static func destination(
        for url: URL
    ) -> Destination? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        let scheme = components.scheme?
            .lowercased()

        let host = components.host?
            .lowercased()

        let path = components.path
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "/")
            .lowercased()

        let sessionId = components.queryItems?
            .first {
                $0.name.lowercased() ==
                    "session_id"
            }?
            .value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        switch scheme {
        case "https":
            guard [
                "chatforia.com",
                "www.chatforia.com",
            ].contains(host) else {
                return nil
            }

            switch path {
            case "mobile/esim/checkout-complete":
                guard let sessionId,
                      !sessionId.isEmpty else {
                    return nil
                }

                return .completed(
                    sessionId: sessionId
                )

            case "mobile/esim/checkout-canceled":
                return .canceled

            default:
                return nil
            }

        case "chatforia":
            guard host == "checkout" else {
                return nil
            }

            switch path {
            case "esim/complete":
                guard let sessionId,
                      !sessionId.isEmpty else {
                    return nil
                }

                return .completed(
                    sessionId: sessionId
                )

            case "esim/canceled":
                return .canceled

            default:
                return nil
            }

        default:
            return nil
        }
    }
}
