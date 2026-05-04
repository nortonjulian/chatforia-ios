import Foundation

struct CountryOption: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let flag: String

    var label: String {
        "\(flag) \(name)"
    }
}
