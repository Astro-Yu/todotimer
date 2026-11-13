import Foundation
#if canImport(XCTest)
import XCTest
@testable import FloatingTodoTimer

@MainActor
final class FloatingTodoTimerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatingTodoTimerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testMaxFiveTasksLimit() {
        let store = TodoStore(storageDirectoryURL: tempDir)
        for i in 1...5 {
            XCTAssertTrue(store.addTask(title: "Task \(i)"))
        }
        XCTAssertEqual(store.items.count, 5)
        XCTAssertFalse(store.canAddMore)
        XCTAssertFalse(store.addTask(title: "Task 6"))
        XCTAssertEqual(store.items.count, 5)
    }

    func testSingleActiveTimerAndSleepAccuracy() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TodoStore(storageDirectoryURL: tempDir, now: t0)
        store.addTask(title: "Task A", now: t0)
        store.addTask(title: "Task B", now: t0)

        let idA = store.items[0].id
        let idB = store.items[1].id

        // Start Task A at t0
        store.toggleTimer(id: idA, now: t0)
        XCTAssertTrue(store.items[0].isRunning)
        XCTAssertFalse(store.items[1].isRunning)

        // 95 seconds later (e.g. after system sleep), start Task B
        let t1 = t0.addingTimeInterval(95)
        store.toggleTimer(id: idB, now: t1)

        // Task A must be automatically paused with 95 accumulated seconds
        XCTAssertFalse(store.items[0].isRunning)
        XCTAssertEqual(store.items[0].accumulatedSeconds, 95)
        XCTAssertEqual(store.items[0].formattedTimerString(at: t1), "01:35")

        // Task B must now be running
        XCTAssertTrue(store.items[1].isRunning)
        let t2 = t1.addingTimeInterval(3661) // 1h 1m 1s
        XCTAssertEqual(store.items[1].formattedTimerString(at: t2), "01:01:01")
    }

    func testCompletingTaskPausesTimerAndUpdatesCompactDisplay() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TodoStore(storageDirectoryURL: tempDir, now: t0)
        store.addTask(title: "First Task", now: t0)
        store.addTask(title: "Second Task", now: t0)

        let id1 = store.items[0].id
        store.toggleTimer(id: id1, now: t0)

        let t1 = t0.addingTimeInterval(40)
        store.toggleComplete(id: id1, now: t1)

        XCTAssertTrue(store.items[0].isCompleted)
        XCTAssertFalse(store.items[0].isRunning)
        XCTAssertEqual(store.items[0].accumulatedSeconds, 40)

        // Compact display should now pick #2 (highest-priority incomplete task)
        let compact = store.compactDisplayTask
        XCTAssertEqual(compact?.priority, 2)
        XCTAssertEqual(compact?.item.title, "Second Task")
    }

    func testCarryOverIncompleteTasksWithAccumulatedTimeAcrossDays() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let storeDay1 = TodoStore(storageDirectoryURL: tempDir, now: day1)
        storeDay1.addTask(title: "Done Yesterday", now: day1)
        storeDay1.addTask(title: "Still Working", now: day1)

        let doneID = storeDay1.items[0].id
        let unfinishedID = storeDay1.items[1].id

        storeDay1.toggleComplete(id: doneID, now: day1)
        storeDay1.toggleTimer(id: unfinishedID, now: day1)
        let day1Later = day1.addingTimeInterval(1800) // 30m
        storeDay1.toggleTimer(id: unfinishedID, now: day1Later) // pause at 30m

        // Next day (+24 hours)
        let day2 = day1.addingTimeInterval(86_400)
        let storeDay2 = TodoStore(storageDirectoryURL: tempDir, now: day2)

        XCTAssertEqual(storeDay2.items.count, 1)
        XCTAssertEqual(storeDay2.items[0].title, "Still Working")
        XCTAssertEqual(storeDay2.items[0].accumulatedSeconds, 1800)
        XCTAssertFalse(storeDay2.items[0].isCompleted)
    }

    func testObsidianMarkdownExportFormat() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TodoStore(storageDirectoryURL: tempDir, now: t0)
        store.addTask(title: "Task Title 1", now: t0)
        store.addTask(title: "Task Title 2", now: t0)

        let id1 = store.items[0].id
        let id2 = store.items[1].id

        // Run Task 1 for 1h 15m (4500s) and complete it
        store.toggleTimer(id: id1, now: t0)
        let t1 = t0.addingTimeInterval(4500)
        store.toggleComplete(id: id1, now: t1)

        // Run Task 2 for 0h 32m (1920s)
        store.toggleTimer(id: id2, now: t1)
        let t2 = t1.addingTimeInterval(1920)

        let markdown = store.generateMarkdown(now: t2)
        let expected = """
        - [x] Task Title 1 (1h 15m)
        - [ ] Task Title 2 (0h 32m)
        """
        XCTAssertEqual(markdown, expected)
    }
}
#endif
