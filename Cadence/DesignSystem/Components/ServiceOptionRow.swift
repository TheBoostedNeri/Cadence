import SwiftUI

/// One music service in a picker, with its badge and a checkmark when selected.
struct ServiceOptionRow: View {
    let service: MusicService
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: service.systemImage)
                .font(Typography.headline)
                .foregroundStyle(Palette.brand)
                .frame(width: IconSize.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(spacing: Spacing.small) {
                    Text(service.name)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                    if service.isRecommended {
                        ServiceBadge(title: String(localized: "Recommended"))
                    } else if let reason = service.unavailableReason {
                        ServiceBadge(title: reason)
                    }
                }
                Text(service.summary)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Spacing.small)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.brand)
                    .accessibilityHidden(true)
            }
        }
        .opacity(service.isAvailable ? Opacity.opaque : Opacity.unavailable)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ServiceBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.badge)
            .foregroundStyle(Palette.brand)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxSmall)
            .background(Palette.brand.opacity(Opacity.tint), in: .capsule)
    }
}
