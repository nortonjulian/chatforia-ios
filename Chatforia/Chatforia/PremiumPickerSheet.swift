import SwiftUI

struct PremiumSelectableOption: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let requiredPlan: AppPlan
}

struct PremiumPickerSheet: View {
    let title: String
    let subtitle: String
    let selectedCode: String
    let currentPlan: AppPlan
    let options: [PremiumSelectableOption]
    let onSelect: (String) -> Void
    let onLockedTap: (PremiumSelectableOption) -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    private var freeOptions: [PremiumSelectableOption] {
        options.filter { $0.requiredPlan == .free }
    }

    private var premiumOptions: [PremiumSelectableOption] {
        options.filter { $0.requiredPlan != .free }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard

                        optionSection(
                            title: "Free",
                            caption: "Included on your current plan.",
                            items: freeOptions
                        )

                        optionSection(
                            title: "Premium",
                            caption: "Visible below and unlockable with Premium.",
                            items: premiumOptions
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)

            HStack(spacing: 8) {
                Text("Current Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(currentPlan.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(themeManager.palette.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.highlightedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func optionSection(
        title: String,
        caption: String,
        items: [PremiumSelectableOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let locked = !currentPlan.canAccess(item.requiredPlan)

                    Button {
                        if locked {
                            onLockedTap(item)
                        } else {
                            onSelect(item.code)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(
                                        locked
                                        ? themeManager.palette.secondaryText.opacity(0.75)
                                        : themeManager.palette.primaryText
                                    )

                                Text(locked ? "Requires \(item.requiredPlan.displayName)" : "Available now")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }

                            Spacer()

                            if selectedCode == item.code && !locked {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(themeManager.palette.accent)
                            } else if locked {
                                Image(systemName: "lock.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.palette.secondaryText)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(themeManager.palette.border)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
