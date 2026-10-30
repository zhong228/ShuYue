import SwiftUI

struct ChapterTitleLayerListView: View {
    @ObservedObject var model: ChapterTitleDesignerModel

    var body: some View {
        List(selection: $model.selectedLayerID) {
            Section {
                Menu {
                    ForEach(ChapterTitleLayerKind.editorCases, id: \.rawValue) { kind in
                        Button {
                            model.add(kind.makeLayer())
                        } label: {
                            Label(localized(kind.titleKey), systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Label(localized("新增元素"), systemImage: "plus")
                }
            }
            .interfaceSectionSurface()

            Section(localized("图层")) {
                if model.draft.layers.isEmpty {
                    ContentUnavailableView {
                        UnavailableLabel(localized("尚无元素"), systemImage: "square.dashed")
                    } description: {
                        Text(localized("加入章节数、章节名、文字、线条、色块或图片。")).foregroundStyle(DSColor.textSecondary)
                    }
                } else {
                    ForEach(model.draft.layers) { layer in
                        layerRow(layer)
                            .tag(layer.id)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    model.setVisible(!layer.isVisible, id: layer.id)
                                } label: {
                                    Label(
                                        localized(layer.isVisible ? "隐藏" : "显示"),
                                        systemImage: layer.isVisible ? "eye.slash" : "eye"
                                    )
                                }
                                Button {
                                    model.setLocked(!layer.isLocked, id: layer.id)
                                } label: {
                                    Label(
                                        localized(layer.isLocked ? "解锁" : "锁定"),
                                        systemImage: layer.isLocked ? "lock.open" : "lock"
                                    )
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.delete(id: layer.id) } label: {
                                    Label(localized("删除"), systemImage: "trash")
                                }
                                Button { model.duplicate(id: layer.id) } label: {
                                    Label(localized("复制"), systemImage: "plus.square.on.square")
                                }
                            }
                            .contextMenu {
                                Button { model.duplicate(id: layer.id) } label: {
                                    Label(localized("复制"), systemImage: "plus.square.on.square")
                                }
                                Button { move(layer, offset: 1) } label: {
                                    Label(localized("向前移动"), systemImage: "square.2.layers.3d.top.filled")
                                }
                                Button { move(layer, offset: -1) } label: {
                                    Label(localized("向后移动"), systemImage: "square.2.layers.3d.bottom.filled")
                                }
                                Button(role: .destructive) { model.delete(id: layer.id) } label: {
                                    Label(localized("删除"), systemImage: "trash")
                                }
                            }
                    }
                    .onMove(perform: model.moveLayer)
                }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }

    private func layerRow(_ layer: ChapterTitleLayer) -> some View {
        Label(layer.name, systemImage: layer.kind.systemImage)
            .badge(localized(layer.kind.titleKey))
            .foregroundStyle(layer.isVisible ? DSColor.textPrimary : DSColor.textSecondary)
            .accessibilityValue(layerAccessibilityValue(layer))
    }

    private func layerAccessibilityValue(_ layer: ChapterTitleLayer) -> String {
        [
            localized(layer.kind.titleKey),
            localized(layer.isVisible ? "显示" : "隐藏"),
            localized(layer.isLocked ? "已锁定" : "未锁定"),
        ].joined(separator: localized("、"))
    }

    private func move(_ layer: ChapterTitleLayer, offset: Int) {
        guard let index = model.draft.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        let destination = min(max(index + offset, 0), model.draft.layers.count - 1)
        guard destination != index else { return }
        model.moveLayer(
            fromOffsets: IndexSet(integer: index),
            toOffset: destination > index ? destination + 1 : destination
        )
    }
}

private extension ChapterTitleLayerKind {
    static let editorCases: [ChapterTitleLayerKind] = [
        .chapterNumber, .chapterName, .originalTitle, .customText,
        .ornament, .line, .colorBlock, .image,
    ]

    var titleKey: String {
        switch self {
        case .chapterNumber: "章节数"
        case .chapterName: "章节名"
        case .originalTitle: "原始标题"
        case .customText: "文字"
        case .ornament: "装饰"
        case .line: "线条"
        case .colorBlock: "色块"
        case .image: "图片"
        }
    }

    var systemImage: String {
        switch self {
        case .chapterNumber: "number"
        case .chapterName: "text.aligncenter"
        case .originalTitle: "textformat"
        case .customText: "character.cursor.ibeam"
        case .ornament: "sparkles"
        case .line: "minus"
        case .colorBlock: "rectangle.fill"
        case .image: "photo"
        }
    }

    func makeLayer() -> ChapterTitleLayer {
        let content: ChapterTitleLayerContent
        switch self {
        case .chapterNumber: content = .dynamic(.number)
        case .chapterName: content = .dynamic(.name)
        case .originalTitle: content = .dynamic(.title)
        case .customText, .ornament: content = .text(localized("文字"))
        case .line: content = .line(.init(width: 1, colorHex: 0x8E8E93, isDashed: false))
        case .colorBlock, .image: content = .none
        }
        return ChapterTitleLayer(
            id: UUID(),
            name: localized(titleKey),
            kind: self,
            frame: .init(x: 0.1, y: 0.35, width: 0.8, height: 0.25),
            rotation: .init(degrees: 0),
            isVisible: true,
            isLocked: false,
            content: content,
            lightStyle: .init(),
            darkStyle: .init()
        )
    }
}

#Preview {
    ChapterTitleLayerListView(
        model: ChapterTitleDesignerModel(initial: .default, onSave: { _ in })
    )
}
