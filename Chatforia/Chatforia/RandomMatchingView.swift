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
                    Text(String(localized: "ios.finding_someone"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(String(localized: "ios.we_re_looking_for_someone_who_s_open_to_chat_right_now"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Text(String(localized: "button_cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle(String(localized: "section_random_chat"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
