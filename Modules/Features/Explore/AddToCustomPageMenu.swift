import SwiftUI

/// 加入自訂頁's choices: each custom explore page, adding the category to it as a 推薦卡片
/// block at its end. A page that shows the category already is ticked and left alone.
struct AddToCustomPageItems: View {
    let reference: ExploreCategoryReference

    @ObservedObject private var store = CustomExplorePageStore.shared

    var body: some View {
        if store.pages.isEmpty {
            Button {} label: {
                Text(localized("尚未建立自訂頁"))
            }
            .disabled(true)
        } else {
            ForEach(store.pages) { page in
                let added = store.page(page.id, contains: reference)
                Button {
                    store.addCategory(reference, toPage: page.id)
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: String(format: localized("已加入「%@」"), page.name)
                    )
                } label: {
                    if added {
                        Label(page.name, systemImage: "checkmark")
                    } else {
                        Text(page.name)
                    }
                }
                .disabled(added)
            }
        }
    }
}

/// 加入自訂頁 as a submenu, for a category's long-press menu.
struct AddToCustomPageMenu: View {
    let reference: ExploreCategoryReference

    var body: some View {
        Menu {
            AddToCustomPageItems(reference: reference)
        } label: {
            Label(localized("加入自訂頁"), systemImage: "rectangle.stack.badge.plus")
        }
    }
}
