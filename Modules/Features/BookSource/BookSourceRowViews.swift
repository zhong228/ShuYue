import SwiftUI

// MARK: - Why these are their own View structs
//
// `List` defers a child view's `body`; it does NOT defer construction of the view
// value a `ForEach` closure returns — and it calls that closure for every element
// (measured: twice per element). While the source row was built by `@ViewBuilder`
// methods on `BookSourceListView`, opening 書源管理 therefore constructed all N rows
// up front: two `Menu` trees per row (~25 items each), the merged row's rotor
// actions, a `ShareLink`, and one full-table scan for the group-name submenus.
// With 3000 imported sources that was ~1.4 s of blocked main thread and 250–345 MB
// resident on a simulator — on device, a screen that never opens.
//
// Measured with a 3000-source list (60 groups): row trees built 6000 → 9, menus
// 6000 → 9, resident 252 MB → 224 MB, main-thread block ~1.4 s → none. The rule this
// encodes: anything inside a `List` row that is more than a couple of views must be
// reached through a `View` struct, never assembled by a method on the parent.
//
// The group-name submenus are gone for the same reason — they built one `Button` per group
// per row, and ran a full pass over `BookSourceStore.sources` to do it. Both now open
// `BookSourceGroupPickerSheet`, which asks `store.groupCounts(excluding:)` once, on open.
//
// Structs were not enough past a few thousand sources: `List` still ran the `ForEach`
// closure for every element on every update. The rows are now hosted one cell at a time by
// `HostedCollectionList`, and rows and groups carry ids instead of `BookSource` copies.

/// One row group in the management list. Every displayed source belongs to exactly one
/// group: pinned sources land in the built-in 置頂／置底 groups, the rest use their
/// `bookSourceGroup` — and sources without one land in the built-in 默認分組 (Legado's
/// default group — ungrouped sources are never left flat).
struct BookSourceRowGroup: Identifiable {
    /// Sentinel ids for the built-in 置頂／置底 groups — kept distinct from any user group
    /// name, so a group literally named 置頂 cannot collide with them.
    static let defaultGroupID = "yuedu.default-group"
    static let topPinnedID = "yuedu.pin-group.top"
    static let bottomPinnedID = "yuedu.pin-group.bottom"

    let id: String
    let name: String
    /// Member ids in display order. Ids, not `BookSource` values: a group of 20,000 sources
    /// used to carry 20,000 copies of every rule string's storage header.
    let sourceIDs: [UUID]

    /// 置頂／置底 are synthetic buckets built from pin state, not from `bookSourceGroup`.
    /// Renaming, merging, or deleting "the group" is meaningless for them, so their menu
    /// only offers the operations that act on the member sources.
    var isPinGroup: Bool {
        id == Self.topPinnedID || id == Self.bottomPinnedID
    }

    /// Computed, not stored: it is only read by the group menu's actions when they run.
    var sourceIds: Set<UUID> { Set(sourceIDs) }
}

/// Native share row for 匯出 …（儲存到「檔案」／AirDrop／…）. See `BookSourceExportFile` for
/// why the payload is a `Transferable` and not a `.fileExporter` document, and
/// `MenuShareLinkPresentationPolicy` for why the share sheet cannot open from this
/// menu before iOS 18.
struct BookSourceExportShareLink: View {
    let label: String
    let filenameLabel: String
    /// Resolved when the row is chosen, not when the menu is built: 匯出全部 over 50,000
    /// sources used to copy the whole library into every render of the toolbar menu.
    let sources: () -> [BookSource]
    /// Where the payload goes before iOS 18: the owning screen shows the share sheet
    /// from its own first-level presenter.
    let onHandoff: (PendingShareExport<BookSourceExportFile>) -> Void

    var body: some View {
        MenuShareRow(
            label: label,
            makeExport: {
                let file = BookSourceExportFile(
                    filename: BookSourceExportFile.filename(for: filenameLabel), sources: sources())
                return PendingShareExport(title: label, name: file.filename, item: file)
            },
            onHandoff: onHandoff
        )
    }
}

// MARK: - Source Row

/// Everything a source row's controls, menu and rotor actions can do. Built once by
/// `BookSourceListView` and handed to every row, so constructing a row costs a few
/// closure retains instead of re-deriving the parent's state.
struct BookSourceRowActions {
    var toggleSelection: (UUID) -> Void
    var toggleEnabled: (UUID) -> Void
    var showInfo: (BookSource) -> Void
    var test: (BookSource) -> Void
    var edit: (BookSource) -> Void
    var copyJSON: (BookSource) -> Void
    /// 匯出書源檔案 — hands the payload to the list's first-level share sheet before
    /// iOS 18. See `MenuShareLinkPresentationPolicy`.
    var export: (PendingShareExport<BookSourceExportFile>) -> Void
    var login: (BookSource) -> Void
    var editVariables: (BookSource) -> Void
    /// Writes a group name to a set of sources; the built-in default group clears the field.
    var applyGroupName: (String, Set<UUID>) -> Void
    /// Opens 移動到分組 — a searchable group list, not a submenu. See
    /// `BookSourceGroupPickerSheet` for why the submenu is gone.
    var pickGroup: (BookSource) -> Void
    var moveToNewGroup: (BookSource) -> Void
    var pinToTop: (BookSource) -> Void
    var pinToBottom: (BookSource) -> Void
    /// The announcement is the caller's, because only the row knows which pin it is dropping.
    var unpin: (BookSource, String) -> Void
    var delete: (BookSource) -> Void
}

/// A modern card-style source row with a distinctive visual identity that does not
/// resemble the classic Legado / 閱讀 management list. Features:
/// - Rounded card container with subtle shadow
/// - Coloured initial-avatar on the leading edge (hash-based hue, not teal)
/// - Compact right-side action stack with capsule buttons
/// - No status stripe; selection is shown by card border instead
struct BookSourceRow: View {
    let source: BookSource
    let isSelected: Bool
    let pin: SourcePinPosition?
    let health: SourceValidationSummary?
    /// Display label of the built-in group for sources with no `bookSourceGroup`.
    let defaultGroupName: String
    let actions: BookSourceRowActions

    /// A warm coral accent used only inside this management surface so the
    /// screen no longer shares the same accent colour palette as the rest of the app.
    private var rowAccent: Color { Color(red: 0.91, green: 0.36, blue: 0.31) }

    @ViewBuilder
    var body: some View {
        let row = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(accessibilityTraits)
            .accessibilityHint(localized("點兩下切換啟用狀態"))
            .accessibilityAction { actions.toggleEnabled(source.id) }
            .accessibilityActions { rotorActions }

        if source.bookSourceUrl.isEmpty {
            row
        } else {
            row.accessibilityCustomContent(
                Text(localized("網址")),
                Text(source.bookSourceUrl)
            )
        }
    }

    // MARK: Visible content

    private var content: some View {
        HStack(spacing: DSSpacing.md) {
            // ── Leading avatar + selection ──
            avatarBlock

            // ── Text block ──
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Text(source.bookSourceName.isEmpty
                        ? localized("未命名書源") : source.bookSourceName)
                        .font(DSFont.bodyBold)
                        .foregroundColor(source.enabled ? DSColor.textPrimary : DSColor.textSecondary)
                        .lineLimit(1)

                    if !source.bookSourceGroup.isEmpty {
                        TagPill(text: source.bookSourceGroup, accent: rowAccent)
                    }
                }

                if !source.bookSourceUrl.isEmpty {
                    Text(source.bookSourceUrl)
                        .font(DSFont.fixed(size: 12))
                        .foregroundColor(DSColor.textTertiary)
                        .lineLimit(1)
                }

                HStack(spacing: DSSpacing.sm) {
                    SourceValidationBadge(summary: health)
                    if pin != nil {
                        PinPill(pin: pin!)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // ── Minimal trailing controls ──
            HStack(spacing: DSSpacing.sm) {
                // Enable / disable capsule button
                Button {
                    actions.toggleEnabled(source.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: source.enabled ? "power" : "poweroff")
                            .font(DSFont.fixed(size: 12))
                        Text(source.enabled ? localized("啟") : localized("停"))
                            .font(DSFont.fixed(size: 11, weight: .semibold))
                    }
                    .foregroundColor(source.enabled ? rowAccent : DSColor.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(source.enabled ? rowAccent.opacity(0.12) : DSColor.neutralControlFill)
                    )
                }
                .buttonStyle(.plain)

                menu
            }
        }
        .padding(.vertical, DSSpacing.lg)
        .padding(.horizontal, DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColor.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? rowAccent.opacity(0.5) : Color.clear,
                    lineWidth: isSelected ? 2.5 : 0
                )
        )
        .opacity(source.enabled ? 1 : 0.55)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }

    // MARK: Avatar block

    private var avatarBlock: some View {
        ZStack {
            // Colourful initial avatar — rounded-rect like an app icon, not a circle
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(avatarColor)
                .frame(width: 48, height: 48)
            Text(avatarInitial)
                .font(DSFont.fixed(size: 18, weight: .bold))
                .foregroundColor(.white)

            // Selection ring
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(rowAccent, lineWidth: 2.5)
                    .frame(width: 52, height: 52)
            }
        }
        .onTapGesture {
            actions.toggleSelection(source.id)
        }
    }

    /// A warm, saturated colour derived from the source URL so the same source always
    /// gets the same avatar colour. Uses a simple hash — not crypto-grade, but stable
    /// and visually distributed enough for a list of hundreds.
    private var avatarColor: Color {
        let hash = source.bookSourceUrl.hashValue
        let hue = abs(Double(hash) / Double(Int.max)).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.65, brightness: 0.75)
    }

    private var avatarInitial: String {
        let name = source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: Menu

    private var menu: some View {
        Menu {
            Button {
                actions.showInfo(source)
            } label: {
                Label(localized("查看詳情"), systemImage: "info.circle")
            }
            Button {
                actions.test(source)
            } label: {
                Label(localized("測試書源"), systemImage: "antenna.radiowaves.left.and.right")
            }
            Divider()
            Button {
                actions.edit(source)
            } label: {
                Label(localized("編輯"), systemImage: "square.and.pencil")
            }
            Button {
                actions.copyJSON(source)
            } label: {
                Label(localized("複製 JSON"), systemImage: "doc.on.doc")
            }
            BookSourceExportShareLink(
                label: localized("匯出"),
                filenameLabel: source.bookSourceName,
                sources: { [source] in [source] },
                onHandoff: actions.export
            )
            if !source.loginUrl.isEmpty {
                Button {
                    actions.login(source)
                } label: {
                    Label(localized("Cookie 驗證登入"), systemImage: "person.badge.key")
                }
            }
            Button {
                actions.editVariables(source)
            } label: {
                Label(localized("設置源變量"), systemImage: "slider.horizontal.3")
            }
            Divider()
            Button {
                actions.pickGroup(source)
            } label: {
                Label(localized("移動到分組"), systemImage: "folder")
            }
            Button {
                actions.moveToNewGroup(source)
            } label: {
                Label(localized("移動到新分組"), systemImage: "folder.badge.plus")
            }
            if !source.bookSourceGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    actions.applyGroupName(defaultGroupName, [source.id])
                } label: {
                    Label(localized("移出分組"), systemImage: "folder.badge.minus")
                }
            }
            Divider()
            if pin == .top {
                Button {
                    actions.unpin(source, localized("已取消置頂"))
                } label: {
                    Label(localized("取消置頂"), systemImage: "pin.slash")
                }
            } else {
                Button {
                    actions.pinToTop(source)
                } label: {
                    Label(localized("置頂"), systemImage: "pin")
                }
            }
            if pin == .bottom {
                Button {
                    actions.unpin(source, localized("已取消置底"))
                } label: {
                    Label(localized("取消置底"), systemImage: "pin.slash.fill")
                }
            } else {
                Button {
                    actions.pinToBottom(source)
                } label: {
                    Label(localized("置底"), systemImage: "pin.fill")
                }
            }
            Divider()
            Button(role: .destructive) {
                actions.delete(source)
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(DSFont.fixed(size: 20))
                .foregroundColor(DSColor.textTertiary.opacity(0.6))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .accessibilityLabel(localized("更多操作"))
    }

    // MARK: Accessibility

    /// The row's VoiceOver name: 書源名稱（分組）, matching the first visible line.
    private var accessibilityLabel: String {
        let name = source.bookSourceName.isEmpty
            ? localized("未命名書源")
            : source.bookSourceName
        guard !source.bookSourceGroup.isEmpty else { return name }
        return "\(name)（\(source.bookSourceGroup)）"
    }

    /// State the row shows visually: the 啟用 toggle, the pin marker, and the validation badge.
    /// Selection is carried by the `.isSelected` trait instead, so it isn't said twice.
    private var accessibilityValue: String {
        var parts = [localized(source.enabled ? "已啟用" : "已停用")]
        if let pin {
            parts.append(localized(pin == .top ? "已置頂" : "已置底"))
        }
        if let health = health?.health {
            parts.append(Self.healthText(health))
        }
        return parts.joined(separator: "，")
    }

    /// `.isSelected` is what carries the leading checkbox — VoiceOver says 「已選取」 for it,
    /// so the value line stays about 啟用 state only.
    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelected {
            // SwiftUI's `AccessibilityTraits.insert` is not `@discardableResult`.
            _ = traits.insert(.isSelected)
        }
        return traits
    }

    static func healthText(_ health: SourceHealth) -> String {
        switch health {
        case .passed:       return localized("驗證通過")
        case .fetchError:   return localized("抓取異常")
        case .contentError: return localized("正文異常")
        }
    }

    /// Everything the row's buttons and menu can do, as rotor actions. Must stay in sync
    /// with the visible controls in `content` — the merged element is the only way
    /// VoiceOver can reach any of them.
    @ViewBuilder
    private var rotorActions: some View {
        Button(localized(isSelected ? "取消選取" : "選取")) {
            actions.toggleSelection(source.id)
        }
        Button(localized("查看詳情")) {
            actions.showInfo(source)
        }
        Button(localized("測試書源")) {
            actions.test(source)
        }
        Button(localized("編輯")) {
            actions.edit(source)
        }
        Button(localized("複製 JSON")) {
            actions.copyJSON(source)
        }
        if !source.loginUrl.isEmpty {
            Button(localized("Cookie 驗證登入")) {
                actions.login(source)
            }
        }
        Button(localized("設置源變量")) {
            actions.editVariables(source)
        }
        // 移動到分組 is now a searchable list rather than a submenu of group names, so the
        // rotor can reach the real thing. 移動到新分組 stays as the quicker typing path.
        Button(localized("移動到分組")) {
            actions.pickGroup(source)
        }
        Button(localized("移動到新分組")) {
            actions.moveToNewGroup(source)
        }
        if !source.bookSourceGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button(localized("移出分組")) {
                actions.applyGroupName(defaultGroupName, [source.id])
            }
        }
        if pin == .top {
            Button(localized("取消置頂")) {
                actions.unpin(source, localized("已取消置頂"))
            }
        } else {
            Button(localized("置頂")) {
                actions.pinToTop(source)
            }
        }
        if pin == .bottom {
            Button(localized("取消置底")) {
                actions.unpin(source, localized("已取消置底"))
            }
        } else {
            Button(localized("置底")) {
                actions.pinToBottom(source)
            }
        }
        Button(localized("刪除"), role: .destructive) {
            actions.delete(source)
        }
    }
}

// MARK: - Group Header Row

/// Group-level operations, built once by `BookSourceListView` like `BookSourceRowActions`.
struct BookSourceGroupActions {
    var toggleExpansion: (String) -> Void
    var rename: (BookSourceRowGroup) -> Void
    /// Opens 合併到其他分組 — the same searchable group list the rows use.
    var pickMergeTarget: (BookSourceRowGroup) -> Void
    var setEnabled: (Set<UUID>, Bool) -> Void
    var select: (Set<UUID>) -> Void
    var copyToPasteboard: (BookSourceRowGroup) -> Void
    /// 匯出該分組 — same first-level share hand-off as `BookSourceRowActions.export`.
    var export: (PendingShareExport<BookSourceExportFile>) -> Void
    var delete: (BookSourceRowGroup) -> Void
    /// Looks the members up when an export actually runs.
    var resolveSources: ([UUID]) -> [BookSource]
}

/// Modern group header with a horizontal gradient strip and chevron, distinct from
/// the classic Legado folder-row style.
struct BookSourceGroupHeaderRow: View {
    let group: BookSourceRowGroup
    let expanded: Bool
    let actions: BookSourceGroupActions

    /// A deep coral accent so the group header reads as part of the same redesigned
    /// surface but distinct from the source rows.
    private var headerAccent: Color { Color(red: 0.85, green: 0.30, blue: 0.22) }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                actions.toggleExpansion(group.id)
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: expanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(DSFont.fixed(size: 20, weight: .medium))
                        .foregroundColor(headerAccent)
                        .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                        .accessibilityHidden(true)

                    Text(group.name)
                        .font(DSFont.bodyBold)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)

                    Text("\(group.sourceIDs.count)")
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundColor(headerAccent)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(headerAccent.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer(minLength: 0)
                }
                .frame(minHeight: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name)，\(group.sourceIDs.count)")
            .accessibilityValue(localized(expanded ? "已展開" : "已收合"))
            .accessibilityHint(localized("點兩下展開或收合分組"))
            .accessibilityAddTraits(.isHeader)

            menu
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            headerAccent.opacity(0.10),
                            headerAccent.opacity(0.03)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.sm)
    }

    /// 分組操作 menu — icons refreshed so the group header no longer reads as the classic
    /// Legado sheet.
    private var menu: some View {
        Menu {
            if !group.isPinGroup {
                Button {
                    actions.rename(group)
                } label: {
                    Label(localized("重命名分組"), systemImage: "character.cursor.ibeam")
                }
                Button {
                    actions.pickMergeTarget(group)
                } label: {
                    Label(localized("合併到其他分組"), systemImage: "arrow.merge")
                }
                Divider()
            }
            Button {
                actions.setEnabled(group.sourceIds, true)
            } label: {
                Label(localized("啟用全部"), systemImage: "bolt.fill")
            }
            Button {
                actions.setEnabled(group.sourceIds, false)
            } label: {
                Label(localized("停用全部"), systemImage: "bolt.slash.fill")
            }
            Divider()
            Button {
                actions.select(group.sourceIds)
            } label: {
                Label(localized("選擇該分組"), systemImage: "checkmark.circle")
            }
            BookSourceExportShareLink(
                label: localized("匯出該分組"),
                filenameLabel: group.name,
                sources: { actions.resolveSources(group.sourceIDs) },
                onHandoff: actions.export
            )
            Button {
                actions.copyToPasteboard(group)
            } label: {
                Label(localized("複製該分組到剪貼簿"), systemImage: "doc.on.doc")
            }
            if !group.isPinGroup {
                Divider()
                Button(role: .destructive) {
                    actions.delete(group)
                } label: {
                    Label(localized("刪除該分組"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(DSFont.fixed(size: 16, weight: .medium))
                .foregroundColor(DSColor.textTertiary)
                .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .accessibilityLabel(localized("分組操作"))
    }
}

// MARK: - Helper Views

/// A small pill-shaped tag used inside the redesigned source row instead of plain parens.
struct TagPill: View {
    let text: String
    var accent: Color = Color.indigo
    var body: some View {
        Text(text)
            .font(DSFont.fixed(size: 11, weight: .medium))
            .foregroundColor(accent.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(accent.opacity(0.10))
            .clipShape(Capsule())
    }
}

/// A compact pin-status pill shown inline beside the validation badge.
struct PinPill: View {
    let pin: SourcePinPosition
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: pin == .top ? "pin.fill" : "pin.fill")
                .font(DSFont.fixed(size: 9))
                .rotationEffect(.degrees(pin == .bottom ? 180 : 0))
            Text(pin == .top ? localized("置頂") : localized("置底"))
                .font(DSFont.fixed(size: 11, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Previews

private func previewSource(
    name: String, group: String = "", enabled: Bool = true
) -> BookSource {
    var source = BookSource(bookSourceUrl: "https://example.com/\(name)", bookSourceName: name)
    source.bookSourceGroup = group
    source.enabled = enabled
    return source
}

private let previewActions = BookSourceRowActions(
    toggleSelection: { _ in }, toggleEnabled: { _ in }, showInfo: { _ in }, test: { _ in },
    edit: { _ in }, copyJSON: { _ in }, export: { _ in }, login: { _ in },
    editVariables: { _ in },
    applyGroupName: { _, _ in }, pickGroup: { _ in }, moveToNewGroup: { _ in },
    pinToTop: { _ in },
    pinToBottom: { _ in }, unpin: { _, _ in }, delete: { _ in }
)

#Preview("書源列 — 新樣式") {
    List {
        BookSourceRow(
            source: previewSource(name: "示例書源", group: "常用"),
            isSelected: false, pin: nil, health: nil, defaultGroupName: "默認分組",
            actions: previewActions
        )
        BookSourceRow(
            source: previewSource(name: "已選取的源"),
            isSelected: true, pin: .top, health: nil, defaultGroupName: "默認分組",
            actions: previewActions
        )
        BookSourceRow(
            source: previewSource(name: "已停用的源", group: "備用", enabled: false),
            isSelected: false, pin: .bottom, health: nil, defaultGroupName: "默認分組",
            actions: previewActions
        )
    }
    .softScrollEdges()
    .listStyle(.plain)
}

private let previewGroupActions = BookSourceGroupActions(
    toggleExpansion: { _ in }, rename: { _ in }, pickMergeTarget: { _ in },
    setEnabled: { _, _ in }, select: { _ in }, copyToPasteboard: { _ in },
    export: { _ in }, delete: { _ in }, resolveSources: { _ in [] })

#Preview("分組表頭 — 新樣式") {
    List {
        BookSourceGroupHeaderRow(
            group: BookSourceRowGroup(id: "常用", name: "常用", sourceIDs: [UUID(), UUID()]),
            expanded: true,
            actions: previewGroupActions
        )
        BookSourceGroupHeaderRow(
            group: BookSourceRowGroup(
                id: BookSourceRowGroup.topPinnedID, name: "置頂組", sourceIDs: [UUID()]),
            expanded: false,
            actions: previewGroupActions
        )
    }
    .softScrollEdges()
    .listStyle(.plain)
}
