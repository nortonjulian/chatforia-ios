import SwiftUI

struct ESIMActivationView: View {
    @StateObject var viewModel: ESIMActivationViewModel

    var body: some View {
        Text("eSIM Activation")
            .navigationTitle("Activate eSIM")
    }
}
