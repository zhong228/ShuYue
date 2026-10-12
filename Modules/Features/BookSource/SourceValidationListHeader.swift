import SwiftUI

/// Which validation outcome the book-source list is filtered to.
enum ValidationListFilter: Hashable { case all, fetchError, contentError }

/// Row badge: last validation verdict + total time, shown under the source URL.
struct SourceValidationBadge: View {
    let summary: SourceValidationSummary?

    var body: some View {
        if let summary {
            HStack(spacing: DSSpacing.xs) {
                HStack(spacing: 3) {
                    Image(systemName: icon(summary.health))
                        .font(DSFont.fixed(size: 10))
                    Text(label(summary.health))
                        .font(DSFont.caption2.weight(.semibold))
                }
                .foregroundColor(color(summary.health))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color(summary.health).opacity(0.14))
                .clipShape(Capsule())

                Text("\(summary.responseMs)ms")
                    .font(DSFont.caption2)
                    .foregroundColor(DSColor.textSecondary.opacity(0.8))
                    .monospacedDigit()
            }
            .padding(.top, 2)
        }
    }

    private func label(_ health: SourceHealth) -> String {
        switch health {
        case .passed:       return localized("驗證通過")
        case .fetchError:   return localized("抓取異常")
        case .contentError: return localized("正文異常")
        }
    }

    private func icon(_ health: SourceHealth) -> String {
        switch health {
        case .passed:       return "checkmark.circle.fill"
        case .fetchError:   return "exclamationmark.triangle.fill"
        case .contentError: return "doc.text.fill"
        }
    }

    private func color(_ health: SourceHealth) -> Color {
        switch health {
        case .passed:       return DSColor.success
        case .fetchError:   return DSColor.warning
        case .contentError: return DSColor.warning
        }
    }
}

/// Stats card + page buttons shown at the top of the book-source list.
/// Counts are computed by `BookSourceManagementModel` once per library or validation
/// change — this used to scan every source four times per render, trimming each
/// `exploreUrl` on the way. Before any run the failure pages read 0.
struct SourceValidationListHeader: View {
    let counts: BookSourceManagementModel.Counts
    @Binding var filter: ValidationListFilter
    /// Grouped ⇄ flat layout switch, parked at the trailing end of the page buttons.
    @Binding var grouped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            statsCard
            pageButtons
        }
        .padding(.vertical, DSSpacing.sm)
    }

    /// Modern dashboard-style stat tiles arranged in a 2×2 grid, replacing the classic
    /// vertical list so the header no longer reads as the Legado / 閱讀 management screen.
    private var statsCard: some View {
        HStack(spacing: DSSpacing.md) {
            statTile(
                icon: "checkmark.circle.fill",
                title: localized("已啟用"),
                value: "\(counts.enabled)",
                total: counts.total,
                tint: Color.indigo
            )
            statTile(
                icon: "safari.fill",
                title: localized("支持發現"),
                value: "\(counts.discover)",
                total: nil,
                tint: Color.orange
            )
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }

    private func statTile(icon: String, title: String, value: String, total: Int?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(DSFont.fixed(size: 14))
                    .foregroundColor(tint)
                Text(title)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(DSFont.title2.weight(.bold))
                    .foregroundColor(DSColor.textPrimary)
                    .monospacedDigit()
                if let total {
                    Text("/ \(total)")
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(DSColor.surface)
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 1)
        )
    }

    /// Modern pill-style segmented page filter. Replaces the classic glass buttons
    /// with a unified capsule strip so the header reads as a contemporary dashboard.
    private var pageButtons: some View {
        HStack(spacing: DSSpacing.sm) {
            ScrollView(.horizontal) {
                pageButtonRow
                    .padding(.vertical, DSSpacing.xs)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            groupingToggle
        }
    }

    private var pageButtonRow: some View {
        HStack(spacing: DSSpacing.sm) {
            pageButton(.all, label: localized("全部"), count: counts.total)
            pageButton(.fetchError, label: localized("抓取異常"), count: counts.fetchError)
            pageButton(.contentError, label: localized("正文異常"), count: counts.contentError)
        }
    }

    /// Grouped ⇄ flat toggle. Modern pill button with filled/active state.
    private var groupingToggle: some View {
        Button {
            grouped.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: grouped ? "rectangle.grid.1x2" : "list.bullet")
                    .font(DSFont.fixed(size: 13))
                Text(grouped ? localized("分組") : localized("列表"))
                    .font(DSFont.fixed(size: 12, weight: .medium))
            }
            .foregroundColor(grouped ? Color.indigo : DSColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(grouped ? Color.indigo.opacity(0.12) : DSColor.neutralControlFill)
            )
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("書源排列方式"))
        .accessibilityValue(localized(grouped ? "分組顯示" : "不分組"))
        .accessibilityHint(localized("點兩下切換分組與不分組"))
    }

    /// A system button with a text label. The label keeps one weight in both states, so
    /// choosing a page never changes the buttons' widths.
    private func pageButton(_ value: ValidationListFilter, label: String, count: Int) -> some View {
        let selected = filter == value
        return Button {
            filter = value
        } label: {
            Text("\(label) \(count)")
                .font(DSFont.subheadline)
                .monospacedDigit()
                .lineLimit(1)
        }
        .sourceFilterButtonStyle(selected: selected)
        // VoiceOver could not tell which page was showing: the selected state was color only.
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Filter buttons
//
// One look for the book-source filter choices: 書源管理's 全部／抓取異常／正文異常 pages
// and 書源驗證's four 失敗類型細分 tiles.

/// Holds a row of filter buttons. iOS 26 blends neighbouring glass shapes only inside
/// one container; earlier systems just lay the buttons out.
struct SourceFilterButtonGroup<Content: View>: View {
    var spacing: CGFloat = DSSpacing.sm
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// The selected choice: prominent (tinted) glass; the others: plain glass. Before
    /// iOS 26 the system bordered styles are the same pair of controls without the
    /// material.
    @ViewBuilder
    func sourceFilterButtonStyle(selected: Bool, shape: ButtonBorderShape = .capsule) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if selected {
                buttonStyle(.glassProminent).buttonBorderShape(shape).tint(DSColor.accent)
            } else {
                buttonStyle(.glass).buttonBorderShape(shape)
            }
        } else {
            legacySourceFilterButtonStyle(selected: selected, shape: shape)
        }
        #else
        legacySourceFilterButtonStyle(selected: selected, shape: shape)
        #endif
    }

    @ViewBuilder
    private func legacySourceFilterButtonStyle(selected: Bool, shape: ButtonBorderShape) -> some View {
        if selected {
            buttonStyle(.borderedProminent).buttonBorderShape(shape).tint(DSColor.accent)
        } else {
            buttonStyle(.bordered).buttonBorderShape(shape)
        }
    }
}

#Preview {
    @Previewable @State var filter: ValidationListFilter = .all
    @Previewable @State var grouped = true
    SourceValidationListHeader(
        counts: BookSourceManagementModel.Counts(
            total: 29, enabled: 29, discover: 27, fetchError: 3, contentError: 1),
        filter: $filter,
        grouped: $grouped
    )
    .padding()
}
