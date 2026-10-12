import SwiftUI

/// Everything Pro adds, as the three benefits of `PremiumPillar`, the tapped feature's
/// first. The offer sells these cards; the member page shows the same cards as what the
/// reader now has, so paying never lands on a list that looks different.
struct PaywallPillarList: View {
    /// The feature that opened the paywall; its pillar leads.
    let leading: PremiumFeature?
    /// Pro is owned: each pillar is marked unlocked.
    var isUnlocked = false

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            ForEach(PremiumPillar.ordered(leading: leading)) { pillar in
                card(pillar)
            }
        }
    }

    private func card(_ pillar: PremiumPillar) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.sm) {
                Label(localized(pillar.titleKey), systemImage: pillar.iconName)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                if isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DSColor.success)
                        .accessibilityLabel(localized("已解鎖"))
                }
            }
            // One element: the pillar's name, then 已解鎖 when owned.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(pillar.benefits) { benefit in
                benefitRow(benefit)
            }
            if let note = pillar.noteKey {
                Text(localized(note))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interfaceCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    private func benefitRow(_ benefit: PremiumBenefit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Image(systemName: benefit.iconName)
                .font(DSFont.body)
                .foregroundStyle(DSColor.accent)
                .frame(width: DSLayout.paywallBenefitIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xs / 2) {
                Text(localized(benefit.titleKey))
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(localized(benefit.detailKey))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One plan as a card: its mark, name, tag, one line about it, and the price. The offer
/// shows the plans as choices; the member page shows the plan they own the same way.
struct PaywallPlanCard: View {
    enum Mark: Equatable {
        /// A plan to pick; `selected` is the one the buy button buys.
        case choice(selected: Bool)
        /// The plan they have.
        case owned
    }

    enum Price: Equatable {
        case hidden
        case loading
        case shown(String)
    }

    let title: String
    let tag: String?
    let detail: String
    let price: Price
    let mark: Mark

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: markSymbol)
                .foregroundStyle(markColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSFont.bodyBold)
                        .foregroundColor(DSColor.textPrimary)
                    if let tag {
                        Text(tag)
                            .font(DSFont.caption2)
                            .foregroundColor(mark == .owned ? DSColor.success : DSColor.accent)
                    }
                }
                Text(detail)
                    .font(DSFont.caption2)
                    .foregroundColor(DSColor.textSecondary)
            }
            Spacer(minLength: 0)
            switch price {
            case .hidden:
                EmptyView()
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .shown(let text):
                Text(text)
                    .font(DSFont.bodyBold)
                    .foregroundColor(DSColor.textPrimary)
            }
        }
        .padding(DSSpacing.lg)
        .interfaceCardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .stroke(isSelected ? DSColor.accent : DSColor.border, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    private var isSelected: Bool {
        mark == .choice(selected: true)
    }

    private var markSymbol: String {
        switch mark {
        case .owned: return "checkmark.circle.fill"
        case .choice(let selected): return selected ? "largecircle.fill.circle" : "circle"
        }
    }

    private var markColor: Color {
        switch mark {
        case .owned: return DSColor.success
        case .choice(let selected): return selected ? DSColor.accent : DSColor.textSecondary
        }
    }
}

#Preview("Paywall components") {
    ScrollView {
        VStack(spacing: DSSpacing.lg) {
            PaywallPlanCard(title: "永久會員", tag: "最超值", detail: "一次付清・約 7.5 個月的月費",
                            price: .shown("US$14.99"), mark: .choice(selected: true))
            PaywallPlanCard(title: "月會員", tag: nil, detail: "每月自動續訂，可隨時取消",
                            price: .loading, mark: .choice(selected: false))
            PaywallPlanCard(title: "永久會員", tag: "目前方案", detail: "一次性購買，永久有效",
                            price: .hidden, mark: .owned)
            PaywallPillarList(leading: .customFonts, isUnlocked: true)
        }
        .padding()
    }
    .softScrollEdges()
}
