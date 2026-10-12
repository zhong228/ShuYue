import XCTest

/// 書架分組：一個原生功能表選「全部」或各分組，選中的分組在同一頁展示它的書——不再有
/// 閱讀式的橫滑翻頁和分組膠囊列。「全部」把每個分組收成一個資料夾，點了推入那個分組的頁面。
///
/// Needs at least one group on the simulator's shelf; it does not create any.
final class BookshelfGroupsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Group menu

    /// The group menu offers 全部 first, then every group, and selecting one switches the shelf.
    @MainActor
    func testMenuSelectsTheShownGroup() throws {
        for isGrid in [false, true] {
            let app = launchShelf(grid: isGrid)
            let menu = groupMenu(in: app)
            let names = groupNames(in: app)

            menu.tap()
            let lastOption = menuOption(app, title: names.last ?? "")
            XCTAssertTrue(lastOption.waitForExistence(timeout: 5), app.debugDescription)
            lastOption.tap()

            XCTAssertTrue(waitUntil(menu, showsValue: names.last ?? ""), "the menu names the chosen group")
            XCTAssertFalse(waitUntil(menu, showsValue: "全部"), "no longer 全部")
            attachScreenshot(of: app, named: "Menu selected the last group, grid \(isGrid)")

            menu.tap()
            let allOption = menuOption(app, title: "全部")
            XCTAssertTrue(allOption.waitForExistence(timeout: 5), app.debugDescription)
            allOption.tap()
            XCTAssertTrue(waitUntil(menu, showsValue: "全部"), "back to 全部")
            app.terminate()
        }
    }

    /// 全部 alone takes no group bar away from the books: the menu is the only switch.
    @MainActor
    func testMenuIsTheOnlyGroupSwitcher() throws {
        let app = launchShelf(grid: false)
        let menu = groupMenu(in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "home_group_chip").count, 0,
                       "the胶囊 chip row is gone — MoYue does not page groups like 閱讀")
        attachScreenshot(of: app, named: "Single group menu")
        XCTAssertTrue(menu.isHittable)
    }

    // MARK: - Folders

    /// 全部 shows one folder per group — the groups' books are inside them, not beside them.
    @MainActor
    func testAllFoldsEachGroupIntoOneFolder() throws {
        for isGrid in [false, true] {
            let app = launchShelf(grid: isGrid)
            let names = groupNames(in: app)
            let shelf = shelf(in: app, grid: isGrid)
            let folders = shelf.descendants(matching: .any).matching(identifier: "home_group_folder")
            XCTAssertTrue(folders.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
            for name in names {
                let folder = folders.matching(NSPredicate(format: "label BEGINSWITH %@", name + "，")).firstMatch
                XCTAssertTrue(folder.exists, "全部 has no folder for \(name): \(app.debugDescription)")
            }
            XCTAssertEqual(folders.count, names.count, "one folder per group")
            attachScreenshot(of: app, named: "全部 with folders, grid \(isGrid)")
            app.terminate()
        }
    }

    /// A folder opens its group's page: the group's name as the title, its books in the
    /// shelf's layout, and 書架's options; back is 全部 again.
    @MainActor
    func testFolderPushesItsGroupsPage() throws {
        for isGrid in [false, true] {
            let app = launchShelf(grid: isGrid)
            _ = groupMenu(in: app)
            let folder = shelf(in: app, grid: isGrid)
                .descendants(matching: .any).matching(identifier: "home_group_folder").firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
            let parts = folder.label.components(separatedBy: "，")
            let group = try XCTUnwrap(parts.first)
            folder.tap()

            let page = app.descendants(matching: .any)[isGrid ? "home_folder_grid" : "home_folder_list"]
            XCTAssertTrue(page.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.navigationBars[group].exists, "the page is titled \(group): \(app.debugDescription)")
            XCTAssertTrue(app.buttons["home_options_menu"].exists, "the group's page has 書架's options")
            XCTAssertFalse(app.buttons["home_add_book"].exists, "adding books stays on 書架")
            XCTAssertEqual(
                page.descendants(matching: .any).matching(identifier: "home_group_folder").count, 0,
                "a group's page lists its books, not folders"
            )
            attachScreenshot(of: app, named: "Folder \(group), grid \(isGrid)")

            app.navigationBars[group].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(shelf(in: app, grid: isGrid).waitForExistence(timeout: 10), "back is 全部")
            XCTAssertTrue(waitUntil(groupMenu(in: app), showsValue: "全部"))
            app.terminate()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func launchShelf(grid: Bool) -> XCUIApplication {
        // A simulator that never answered the notification prompt shows it at launch, and
        // SpringBoard's alert takes every touch meant for the shelf until it is answered.
        addUIInterruptionMonitor(withDescription: "System permission prompt") { alert in
            alert.buttons.element(boundBy: 0).tap()
            return true
        }
        let app = XCUIApplication()
        app.launchArguments = ["-yd_root_tab_visible_ids", "(bookshelf, settings)",
                               "-bookLayoutIsGrid", grid ? "YES" : "NO",
                               "-bookSortOrder", "manual"]
        app.launch()
        return app
    }

    /// The single native group menu on the shelf, e.g. `全部 ▾`.
    @MainActor
    private func groupMenu(in app: XCUIApplication) -> XCUIElement {
        let menu = app.buttons["home_group_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), app.debugDescription)
        return menu
    }

    /// The shelf's group names, 全部 excluded: every group the shelf can select. 全部
    /// folds each group into one folder, whose label starts with the group's name —
    /// read from 全部's folders, so the test never pokes at the menu's internal layout.
    @MainActor
    private func groupNames(in app: XCUIApplication) -> [String] {
        let shelf = shelf(in: app, grid: false)
        let folders = shelf.descendants(matching: .any).matching(identifier: "home_group_folder")
        XCTAssertTrue(folders.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        let names = folders.allElementsBoundByIndex.compactMap { folder -> String? in
            folder.label.components(separatedBy: "，").first
        }
        XCTAssertGreaterThanOrEqual(names.count, 1, "the shelf needs at least one group")
        return names
    }

    /// One option of the open group menu, matched by its label.
    @MainActor
    private func menuOption(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func shelf(in app: XCUIApplication, grid: Bool) -> XCUIElement {
        let shelf = app.descendants(matching: .any)[grid ? "home_book_grid" : "home_book_list"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
        return shelf
    }

    @MainActor
    private func waitUntil(_ element: XCUIElement, showsValue value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}