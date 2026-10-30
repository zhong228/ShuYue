import SwiftUI
import UIKit

/// 預設封面 — what a book without its own cover shows.
///
/// Legado keeps one default cover per appearance; this keeps a small library and
/// picks one per book (deterministically, see `DefaultCoverLibrary`), so a shelf
/// of coverless books doesn't turn into the same picture repeated. With the
/// library empty the book falls through to `GeneratedBookCover`.
struct DefaultCoverSettingsView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @State private var importErrorMessage: String?

    private var cornerRadiusText: String {
        String(format: localized("%d pt"), Int(settings.bookshelfCoverCornerRadius.rounded()))
    }

    var body: some View {
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(spacing: DSSpacing.lg) {
                // 分组卡片：预設封面各 Section 合为卡片，替代系统 Form Section（2026-10-25）。
                DSSettingsGroupCard(title: "", footer: {
                    Text(localized("开启后所有书籍都使用预设封面，忽略书籍自带的封面图。"))
                        .dsSectionFooter()
                }) {
                    DSSettingsCardToggle(
                        title: localized("强制使用预设封面"),
                        systemImage: "photo.on.rectangle.angled",
                        isOn: $settings.useDefaultCoverForAllBooks
                    )
                }

                DSSettingsGroupCard(title: "", footer: {
                    Text(localized("用于书架卡片中的封面裁切，不影响卡片背景圆角。"))
                        .dsSectionFooter()
                }) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text(localized("封面圆角"))
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text(cornerRadiusText)
                                .font(DSFont.subheadline)
                                .foregroundStyle(DSColor.textSecondary)
                                // The slider below speaks this value; read on its own
                                // it is just a loose number.
                                .accessibilityHidden(true)
                        }
                        Slider(
                            value: $settings.bookshelfCoverCornerRadius,
                            in: GlobalSettings.bookshelfCoverCornerRadiusRange,
                            step: 1
                        )
                        // A Slider has no label of its own and would otherwise
                        // announce a bare percentage of its range.
                        .accessibilityLabel(localized("封面圆角"))
                        .accessibilityValue(cornerRadiusText)
                    }
                    .dsSettingsCardRow(minHeight: 0)
                    .padding(.vertical, DSSpacing.xs)
                }

                DSSettingsGroupCard(title: "", footer: {
                    Text(localized("开启后，探索页中没有封面的书卡也使用随机预设封面图（列表和网格均生效）。"))
                        .dsSectionFooter()
                }) {
                    DSSettingsCardToggle(
                        title: localized("探索页启用预设封面"),
                        systemImage: "sparkles.rectangle.stack",
                        isOn: $settings.exploreUsesDefaultCover
                    )
                }

                DSSettingsGroupCard(title: "", footer: {
                    Text(localized("开启后，汇入本地书籍时会自动搜索并替无封面书籍套用网路封面。"))
                        .dsSectionFooter()
                }) {
                    DSSettingsCardToggle(
                        title: localized("汇入书籍后自动刮削封面"),
                        systemImage: "wand.and.stars",
                        isOn: $settings.autoScrapeCovers
                    )
                }

                DSSettingsGroupCard(title: localized("自动生成的封面"), footer: {
                    Text(localized("只影响自动生成的封面，你汇入的封面图不受影响。"))
                        .dsSectionFooter()
                }) {
                    DSSettingsCardToggle(
                        title: localized("封面显示书名"),
                        systemImage: "textformat",
                        isOn: $settings.defaultCoverDrawsBookName
                    )
                    DSSettingsCardDivider()
                    DSSettingsCardToggle(
                        title: localized("封面显示作者"),
                        systemImage: "person.text.rectangle",
                        isOn: $settings.defaultCoverDrawsBookAuthor
                    )
                }

                coverLibrarySection(for: .light)
                coverLibrarySection(for: .dark)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.xxl * 2)
        }
        }
        .softScrollEdges()
        .navigationTitle(localized("预设封面"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(
            localized("封面汇入失败"),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func coverLibrarySection(for scheme: DefaultCoverScheme) -> some View {
        let fileNames = settings.defaultCoverFileNames(for: scheme)

        DSSettingsGroupCard(title: scheme.title, footer: {
            Text(
                scheme == .dark
                    ? localized("深色模式下优先使用这里的封面，未设置时跟随亮色封面。")
                    : localized("书籍没有封面时随机使用其中一张作为预设封面。")
            )
            .dsSectionFooter()
        }) {
            if fileNames.isEmpty {
                Text(
                    scheme == .dark
                        ? localized("暂无深色封面，未设置时使用亮色封面")
                        : localized("暂无封面，点击下方按钮添加")
                )
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .dsSettingsCardRow(minHeight: 0)
                .padding(.vertical, DSSpacing.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.md) {
                        ForEach(fileNames, id: \.self) { fileName in
                            coverThumbnail(fileName: fileName, scheme: scheme)
                        }
                    }
                    .padding(.vertical, DSSpacing.xs)
                    .padding(.horizontal, DSSpacing.md)
                }
                .dsSettingsCardRow(minHeight: 0)
            }

            DSSettingsCardDivider()

            ImageSourcePickerButton(
                accessibilityTitle: scheme == .dark
                    ? localized("添加深色封面图")
                    : localized("添加封面图"),
                onPick: { result in handlePick(result, for: scheme) }
            ) {
                Label(
                    scheme == .dark ? localized("添加深色封面图") : localized("添加封面图"),
                    systemImage: "photo.badge.plus"
                )
            }
            .dsSettingsCardRow(minHeight: 44)
        }
    }

    @ViewBuilder
    private func coverThumbnail(fileName: String, scheme: DefaultCoverScheme) -> some View {
        let image = DefaultCoverLibrary.image(fileName: fileName)

        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // The file is gone (deleted outside the app, failed restore):
                    // show the slot as broken rather than an invisible gap.
                    Rectangle().fill(DSColor.neutralControlFill)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(DSColor.textSecondary)
                                .accessibilityHidden(true)
                        )
                }
            }
            .frame(
                width: DSLayout.searchResultCoverWidth,
                height: DSLayout.searchResultCoverHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .stroke(DSColor.textSecondary.opacity(0.2), lineWidth: 0.5)
            )

            Button(role: .destructive) {
                settings.removeDefaultCover(fileName: fileName, for: scheme)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DSFont.fixed(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, DSColor.destructive)
            }
            .buttonStyle(.plain)
            .padding(DSSpacing.xs)
            .accessibilityLabel(localized("移除这张封面"))
        }
    }

    private func handlePick(
        _ result: Result<PickedImageSource, PickedImageError>,
        for scheme: DefaultCoverScheme
    ) {
        do {
            switch result {
            case .success(.data(let data)):
                try settings.importDefaultCover(data: data, for: scheme)
            case .success(.file(let url)):
                try settings.importDefaultCover(from: url, for: scheme)
            case .failure(let error):
                importErrorMessage = localized(error.messageKey)
            }
        } catch let error as DefaultCoverStorageError {
            importErrorMessage = localized(error.messageKey)
        } catch {
            importErrorMessage = localized("无法读取图片。")
        }
    }
}

#Preview {
    NavigationStack {
        DefaultCoverSettingsView()
    }
}