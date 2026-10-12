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
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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

#Preview {
    Form {
        Section {
            NavigationLink {} label: {
                SettingsValueLabel(title: "排版生效範圍", systemImage: "paintpalette", value: "全部跟隨全域")
            }
            Toggle(isOn: .constant(true)) {
                SettingsRowLabel("粗體", systemImage: "bold")
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
                SettingsRowLabel("重設排版", systemImage: "arrow.counterclockwise", role: .action)
            }
            SettingsLockedRow(title: "正則高亮", systemImage: "text.magnifyingglass") {}
        }
    }
}
