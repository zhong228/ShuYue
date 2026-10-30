import SwiftUI
import UniformTypeIdentifiers

/// Uploads and folder changes are explicit operations scoped to the location the
/// user opened. A failed mutation never refreshes the catalog as if it succeeded.
struct RemoteLibraryManagementView: View {
    let connectionID: String
    let directoryURL: URL
    @Environment(\.appDependencies) private var dependencies
    @State private var capabilities: RemoteLibraryWriteCapabilities?
    @State private var loading = true
    @State private var importing = false
    @State private var folderName = ""
    @State private var task: Task<Void, Never>?
    @State private var isWorking = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            if loading {
                Section { ProgressView(localized("正在检查书库功能")) }.interfaceSectionSurface()
            }
            if let capabilities {
                if capabilities.canUpload {
                    Section {
                        Button { importing = true } label: {
                            Label(localized("上传书籍到此书库"), systemImage: "arrow.up.doc")
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text(localized("选取的档案会传送到目前的远端书库；不会自动加入本机书架。"))
                            .dsSectionFooter()
                    }
                    .interfaceSectionSurface()
                }
                if capabilities.canCreateFolder {
                    Section {
                        TextField(localized("资料夹名称"), text: $folderName)
                            .autocorrectionDisabled()
                        Button(localized("建立资料夹")) {
                            let name = folderName
                            perform {
                                _ = try await dependencies.remoteLibraryWriting.createFolder(name: name,
                                    connectionID: connectionID, directoryURL: directoryURL)
                                folderName = ""
                            }
                        }
                        .disabled(isWorking || folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .interfaceSectionSurface()
                }
                if let reason = capabilities.unsupportedReasonKey {
                    Section {
                        Label(localized(reason), systemImage: "info.circle")
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()
                }
            }
            if isWorking {
                Section {
                    ProgressView(localized("正在更新远端书库"))
                    Button(localized("取消"), role: .cancel) { task?.cancel() }
                }
                .interfaceSectionSurface()
            }
            if let message {
                Section {
                    Label(message, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(failed ? DSColor.destructive : DSColor.textSecondary)
                    if capabilities == nil {
                        Button(localized("重试")) { task = Task { await loadCapabilities() } }
                    }
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("管理远端书库"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .task { await loadCapabilities() }
        .onDisappear { task?.cancel() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: ["epub", "pdf", "txt", "md", "markdown"].compactMap { UTType(filenameExtension: $0) },
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                perform {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    _ = try await dependencies.remoteLibraryWriting.upload(fileURL: url,
                        connectionID: connectionID, directoryURL: directoryURL)
                }
            case .failure(let error):
                message = error.localizedDescription; failed = true
            }
        }
    }

    private func loadCapabilities() async {
        loading = true
        defer { loading = false }
        do {
            capabilities = try await dependencies.remoteLibraryWriting.capabilities(
                connectionID: connectionID, directoryURL: directoryURL)
            message = nil
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription; failed = true
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true; message = nil
        task = Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                message = localized("远端书库已更新")
                failed = false
                UIAccessibility.post(notification: .announcement, argument: message)
            } catch {
                message = Task.isCancelled ? localized("操作已取消，请重新整理书库确认伺服器状态") : error.localizedDescription
                failed = true
            }
        }
    }
}

struct RemoteLibraryBookEditor: View {
    let item: RemoteLibraryItem
    let capabilities: RemoteLibraryWriteCapabilities
    let onSaved: (RemoteLibraryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDependencies) private var dependencies
    @EnvironmentObject private var store: BookStore
    @State private var title: String
    @State private var author: String
    @State private var filename: String
    @State private var working = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    init(item: RemoteLibraryItem, capabilities: RemoteLibraryWriteCapabilities,
         onSaved: @escaping (RemoteLibraryItem) -> Void) {
        self.item = item; self.capabilities = capabilities; self.onSaved = onSaved
        _title = State(initialValue: item.title)
        _author = State(initialValue: item.author ?? "")
        _filename = State(initialValue: item.formats.first?.url.lastPathComponent ?? "")
    }

    var body: some View {
        Form {
            Section {
                if capabilities.canEditMetadata {
                    TextField(localized("书名"), text: $title)
                    TextField(localized("作者"), text: $author)
                } else if capabilities.canMove {
                    TextField(localized("档案名称"), text: $filename).autocorrectionDisabled()
                }
            } footer: {
                Text(localized("储存会修改远端书库，本机阅读进度和书签会保留。"))
                    .dsSectionFooter()
            }
            .disabled(working)
            .interfaceSectionSurface()
            if working {
                Section {
                    ProgressView(localized("正在更新远端书库"))
                    Button(localized("取消"), role: .cancel) { task?.cancel() }
                }.interfaceSectionSurface()
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DSColor.destructive)
                }.interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("编辑远端资料"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Label(localized("储存"), systemImage: "checkmark").labelStyle(.iconOnly)
                }.disabled(working || (capabilities.canEditMetadata ? title : filename).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (capabilities.canEditMetadata && author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func save() {
        guard !working else { return }
        working = true; errorMessage = nil
        task = Task { @MainActor in
            defer { working = false }
            do {
                let updated: RemoteLibraryItem
                if capabilities.canEditMetadata {
                    try await dependencies.remoteLibraryWriting.updateMetadata(item: item, title: title,
                        authors: author.isEmpty ? [] : [author], readingStore: store)
                    updated = RemoteLibraryItem(id: item.id, connectionID: item.connectionID, title: title,
                        author: author, summary: item.summary, coverURL: item.coverURL, formats: item.formats)
                } else {
                    let url = try await dependencies.remoteLibraryWriting.move(item: item, toName: filename, readingStore: store)
                    guard let original = item.formats.first else { throw RemoteLibraryError.unsupportedFormat }
                    updated = RemoteLibraryItem(id: url.absoluteString, connectionID: item.connectionID,
                        title: url.deletingPathExtension().lastPathComponent, author: item.author, summary: item.summary,
                        coverURL: item.coverURL, formats: [RemoteLibraryFormat(url: url, fileExtension: original.fileExtension,
                            mimeType: original.mimeType, size: original.size)])
                }
                onSaved(updated)
                UIAccessibility.post(notification: .announcement, argument: localized("远端书库已更新"))
                dismiss()
            } catch {
                errorMessage = Task.isCancelled ? localized("操作已取消，请重新整理书库确认伺服器状态") : error.localizedDescription
            }
        }
    }
}

struct CalibreProgressStatusView: View {
    let bookID: UUID
    @ObservedObject var service: CalibreProgressService

    var body: some View {
        Section(localized("Calibre 阅读进度")) {
            switch service.state(for: bookID) {
            case .idle:
                Text(localized("阅读时会回传可精确对应的位置"))
                    .foregroundStyle(DSColor.textSecondary)
            case .syncing:
                ProgressView(localized("正在回传阅读进度"))
            case .synced:
                Label(localized("阅读进度已回传"), systemImage: "checkmark.circle")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(DSColor.destructive)
                Button(localized("重新回传进度")) { Task { await service.retry(bookID: bookID) } }
            }
        }
        .interfaceSectionSurface()
    }
}
