import XCTest
@testable import ClipBoard

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ClipBoardTests-\(UUID().uuidString)")!
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipBoardTests-\(UUID().uuidString)/history.json")
    }

    override func tearDown() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        defaults = nil
        fileURL = nil
        super.tearDown()
    }

    func testNewestFirstAndConsecutiveDeduplication() {
        let settings = SettingsManager(defaults: defaults)
        let store = ClipboardStore(settings: settings, fileURL: fileURL)
        store.add("first", at: Date(timeIntervalSince1970: 1))
        store.add("second", at: Date(timeIntervalSince1970: 2))
        store.add("second", at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(store.items.map(\.content), ["second", "first"])
    }

    func testPinnedItemsSurviveHistoryCleanup() {
        let settings = SettingsManager(defaults: defaults)
        settings.historyLimit = 10
        let store = ClipboardStore(settings: settings, fileURL: fileURL)
        for index in 0..<12 { store.add("item-\(index)") }
        let oldestVisible = store.items.last!
        store.togglePin(oldestVisible.id)
        for index in 12..<25 { store.add("item-\(index)") }
        XCTAssertTrue(store.items.contains(where: { $0.id == oldestVisible.id && $0.isPinned }))
        XCTAssertEqual(store.items.count, 10)
    }

    func testPersistenceAndCaseInsensitiveSearch() {
        let settings = SettingsManager(defaults: defaults)
        var store: ClipboardStore? = ClipboardStore(settings: settings, fileURL: fileURL)
        store?.add("Docker Compose")
        store = nil

        let restored = ClipboardStore(settings: settings, fileURL: fileURL)
        XCTAssertEqual(restored.filtered(by: "docker").first?.content, "Docker Compose")
    }
}
