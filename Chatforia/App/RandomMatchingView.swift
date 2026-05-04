import SwiftUI

struct RandomMatchingView: View {
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                ProgressView()
                    .scaleEffect(1.5)

                VStack(spacing: 10) {
                    Text("Finding someone…")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("We’re looking for someone who’s open to chat right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Random Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
