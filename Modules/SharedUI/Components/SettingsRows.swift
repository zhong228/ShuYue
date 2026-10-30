import SwiftUI

/// A NavigationLink whose label is a 书悦 settings row — the same coloured badge,
/// title, trailing value and chevron as `DSSettingsRow`, for rows that push a page
/// rather than open a sheet. `SettingsView` uses it for 外觀主題 / 診斷與回報 / 關於.
struct DSSettingsNavRow<Destination: View>: View {
    let icon: String
    let title: String
    var value: String? = nil
    let destination: Destination

    init(icon: String, title: String, value: String? = nil,
         @ViewBuilder destination: () -> Destination) {
        self.icon = icon
        self.title = title
        self.value = value
        self.destination = destination()
    }

    var body: some View {
        // A NavigationLink on a Form/List row already draws the system disclosure
        // indicator; the label must not add its own chevron or the row shows two ">".
        NavigationLink(destination: destination) {
            HStack(spacing: DSSpacing.md) {
                DSIconBadge(systemImage: icon,
                            gradient: DSBrandGradient.tint(for: icon))
                Text(title)
                    .font(DSFont.body)
                    .foregroundColor(DSColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: DSSpacing.sm)
                if let value {
                    Text(value)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The rows settings screens are built from — 設定, 閱讀設定, 外觀主題, 主題自訂 — so every
/// row of every kind wears the same symbol at the same size, in the same colour, with its
/// title on the same line. Each wraps a native control; these only fix the label.
///
/// The symbol style is `IconConsistentLabelStyle`, the one `DSSettingsRow` has always used
/// on 設定, so the pages it opens look like part of it.
struct SettingsRowLabel: View {
    enum Role {
        /// A setting, a page, a toggle: the title reads as text.
        case standard
        /// Does something when tapped — 匯出, 匯入, 重設: the title takes the tint.
        case action
        /// Removes or overwrites something the user made.
        case destructive
    }

    let title: String
    let systemImage: String
    var role: Role = .standard

    init(_ title: String, systemImage: String, role: Role = .standard) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            iconBadge
            Text(title)
                .foregroundStyle(foreground)
        }
    }

    @ViewBuilder
    private var iconBadge: some View {
        switch role {
        case .standard:
            DSIconBadge(
                systemImage: systemImage,
                gradient: DSBrandGradient.tint(for: systemImage)
            )
        case .action:
            DSIconBadge(
                systemImage: systemImage,
                gradient: [Color.accentColor, Color.accentColor.opacity(0.72)]
            )
        case .destructive:
            DSIconBadge(
                systemImage: systemImage,
                gradient: [DSColor.destructive, DSColor.destructive.opacity(0.72)]
            )
        }
    }

    private var foreground: AnyShapeStyle {
        switch role {
        case .standard: return AnyShapeStyle(DSColor.textPrimary)
        case .action: return AnyShapeStyle(.tint)
        case .destructive: return AnyShapeStyle(DSColor.destructive)
        }
    }
}

/// A title with its current value on the right: the label of a row that opens a page.
struct SettingsValueLabel: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(DSColor.textSecondary)
        } label: {
            SettingsRowLabel(title, systemImage: systemImage)
        }
    }
}

/// `LabeledContent(title, value:)` in the theme's text colours: the title as 主文字, the
/// value as 次級文字. The plain initializer draws both in the system's own colours, which
/// 外觀主題 › 文字顏色 cannot reach. Layout and VoiceOver are LabeledContent's own.
struct ThemedLabeledContent: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(DSColor.textSecondary)
        } label: {
            Text(title)
                .foregroundStyle(DSColor.textPrimary)
        }
    }
}

/// The label of a `ContentUnavailableView` in the theme's text colours: the title as 主文字,
/// the symbol as 次級文字 — what the view gives them itself, in the system's colours,
/// which 外觀主題 › 文字顏色 cannot reach. The description goes in 次級文字 at the call site.
struct UnavailableLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(DSColor.textPrimary)
        } icon: {
            // 书悦空态图标：朱砂浅染圆角方块里的品牌描边图标，替代 ContentUnavailableView
            // 的纯线性图标——全 App 的空态统一成"书卷印章"气质。
            Image(systemName: systemImage)
                .font(DSFont.fixed(size: 20, weight: .semibold))
                .foregroundStyle(DSColor.appAccent)
                .frame(width: 52, height: 52)
                .background(
                    DSColor.appAccentSoft,
                    in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                        .stroke(DSColor.appAccentOutline, lineWidth: 1)
                }
        }
    }
}

/// A value adjusted by dragging: title and value on one line, the slider under them.
struct SettingsSliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    let systemImage: String
    /// Shown on the right and spoken as the slider's value — one string for both, so
    /// what VoiceOver says can never drift from what is on screen.
    let valueText: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            LabeledContent {
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
            } label: {
                SettingsRowLabel(title, systemImage: systemImage)
            }
            // The slider below carries both; read once, not twice.
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A Pro control seen without Pro: its name, 需要 Pro and a lock, opening the paywall.
/// In view rather than hidden — a reader has to see a feature where it would be used
/// to want it (2026-09-27).
struct SettingsLockedRow: View {
    let title: String
    let systemImage: String
    let onOpenPaywall: () -> Void

    var body: some View {
        Button(action: onOpenPaywall) {
            LabeledContent {
                HStack(spacing: DSSpacing.xs) {
                    Text(localized("需要 Pro"))
                    Image(systemName: "lock.fill")
                        .font(DSFont.caption)
                }
                .foregroundStyle(DSColor.textSecondary)
                // Spoken once, as the row's value below.
                .accessibilityHidden(true)
            } label: {
                SettingsRowLabel(title, systemImage: systemImage)
            }
        }
        .accessibilityValue(localized("需要 Pro"))
    }
}

/// A card-style settings item for grid layouts.
struct DSSettingsCard: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                DSIconBadge(systemImage: icon, gradient: DSBrandGradient.tint(for: icon), side: 30, iconSize: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DSFont.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(DSColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(DSFont.caption)
                            .foregroundColor(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundColor(DSColor.textTertiary)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(DSColor.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A grouped settings card: a section title above a rounded surface card whose rows
/// sit on hairline dividers. The card vocabulary the rebuilt settings pages share
/// (我的 → 设置, 视觉主题, 关于, 诊断) — an alternative to `List` sections.
struct DSSettingsGroupCard<Footer: View, Content: View>: View {
    let title: String
    /// Carried onto the title so a rebuilt page can keep an accessibility identifier a UI
    /// test already looks up (`tts_builtin_section`, …) — a card's title replaces the
    /// `Section` header the identifier used to sit on.
    let titleAccessibilityIdentifier: String?
    @ViewBuilder let footer: Footer
    @ViewBuilder let content: Content

    init(
        title: String,
        titleAccessibilityIdentifier: String? = nil,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.footer = footer()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            titleLabel
                .padding(.horizontal, DSSpacing.sm)
                .padding(.top, DSSpacing.xs)

            VStack(spacing: 0) { content }
                .background(cardSurface)
                .overlay(cardBorder)

            footer
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.sm)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        let label = Text(title)
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
        if let titleAccessibilityIdentifier {
            label.accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            label
        }
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(DSColor.surface)
            .shadow(color: DSColor.shadow, radius: 3, x: 0, y: 1)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5)
    }
}

/// The hairline between two rows inside a `DSSettingsGroupCard`. The 50pt leading
/// keeps it under the text, past the 30pt badge + its 8pt gap + 12pt padding.
struct DSSettingsCardDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 50)
    }
}

/// The 54pt rhythm of a card row, for bespoke content — a preview, a slider, a
/// label/value pair — that is not one of the shared rows: full width, horizontally
/// inset by `DSSpacing.md`, tappable edge to edge. The frame the shared card rows
/// (`DSSettingsCardRow`, `DSSettingsCardToggle`, …) draw for themselves.
struct DSSettingsCardRowFrame: ViewModifier {
    var minHeight: CGFloat = 54

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(.horizontal, DSSpacing.md)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Wraps bespoke content in a settings card's row rhythm. See `DSSettingsCardRowFrame`.
    func dsSettingsCardRow(minHeight: CGFloat = 54) -> some View {
        modifier(DSSettingsCardRowFrame(minHeight: minHeight))
    }
}

/// `LabeledContent(title, value:)` inside a card row: title as 主文字 on the left,
/// value as 次級文字 on the right, in the card's 54pt rhythm.
struct DSSettingsCardValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .font(DSFont.body)
                .foregroundColor(DSColor.textPrimary)
            Spacer(minLength: DSSpacing.sm)
            Text(value)
                .font(DSFont.caption)
                .foregroundColor(DSColor.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .dsSettingsCardRow()
    }
}

/// A destructive (or tinted) action row inside a settings card: badge + title in
/// the role's colour, in the card's 54pt rhythm. The card answer to a `List` row
/// whose `Button` carried a `Label`.
struct DSSettingsCardActionRow: View {
    let title: String
    let systemImage: String
    var role: SettingsRowLabel.Role = .action
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(title, systemImage: systemImage, role: role)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
    }
}

/// Shared label for settings-card rows: badge, title, optional detail, a trailing
/// value, and the chevron — or a lock for Pro-gated rows. Worn by both the button
/// (sheet) and NavigationLink (push) flavours below.
private struct SettingsCardRowLabel: View {
    let icon: String
    let title: String
    let detail: String?
    let value: String?
    let isLocked: Bool

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            DSIconBadge(
                systemImage: icon,
                gradient: DSBrandGradient.tint(for: icon),
                side: 30,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundColor(DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: DSSpacing.sm)

            if let value {
                Text(value)
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
                    .lineLimit(1)
            }

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundColor(DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A tappable settings-card row: badge + title (+ detail/value) + chevron, opening
/// a sheet or performing an action. The card answer to `DSSettingsCard` for the
/// rebuilt single-column 我的 page.
struct DSSettingsCardRow: View {
    let icon: String
    let title: String
    let detail: String?
    let value: String?
    let isLocked: Bool
    let action: () -> Void

    init(
        icon: String,
        title: String,
        detail: String? = nil,
        value: String? = nil,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.value = value
        self.isLocked = isLocked
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsCardRowLabel(
                icon: icon,
                title: title,
                detail: detail,
                value: value,
                isLocked: isLocked
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(value ?? "")
    }
}

/// A settings-card row that pushes a page — the NavigationLink flavour of
/// `DSSettingsCardRow`, for rebuilds that still drill down inside an enclosing
/// NavigationStack.
struct DSSettingsCardNavRow<Destination: View>: View {
    let icon: String
    let title: String
    let detail: String?
    let value: String?
    let isLocked: Bool
    let destination: Destination

    init(
        icon: String,
        title: String,
        detail: String? = nil,
        value: String? = nil,
        isLocked: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.value = value
        self.isLocked = isLocked
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsCardRowLabel(
                icon: icon,
                title: title,
                detail: detail,
                value: value,
                isLocked: isLocked
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(value ?? "")
    }
}

/// A Toggle whose label is a settings row (badge + title), sized to the same
/// 54pt rhythm as `DSSettingsCardRow` so a card of rows reads as one list.
struct DSSettingsCardToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var detail: String? = nil

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: DSSpacing.sm) {
                SettingsRowLabel(title, systemImage: systemImage)
                if let detail {
                    Spacer(minLength: DSSpacing.sm)
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

/// A Picker whose label is a settings row (badge + title), sized to the same
/// row rhythm as `DSSettingsCardRow`.
struct DSSettingsCardPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(selection: $selection) {
            content
        } label: {
            SettingsRowLabel(title, systemImage: systemImage)
        }
        .pickerStyle(.menu)
        .padding(.horizontal, DSSpacing.md)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

#Preview {
    Form {
        Section {
            NavigationLink {} label: {
                SettingsValueLabel(title: "排版生效范围", systemImage: "paintpalette", value: "全部跟随全域")
            }
            Toggle(isOn: .constant(true)) {
                SettingsRowLabel("粗体", systemImage: "bold")
            }
            SettingsSliderRow(
                title: "行距",
                systemImage: "arrow.up.and.down.text.horizontal",
                valueText: "1.65",
                value: .constant(1.65),
                range: 1.0...2.4,
                step: 0.05
            )
            Button {} label: {
                SettingsRowLabel("重设排版", systemImage: "arrow.counterclockwise", role: .action)
            }
            SettingsLockedRow(title: "正则高亮", systemImage: "text.magnifyingglass") {}
        }
    }
}
