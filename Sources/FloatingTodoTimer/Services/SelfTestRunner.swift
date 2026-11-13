import Foundation

@MainActor
enum SelfTestRunner {
    static func runAll() -> Int32 {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatingTodoTimerSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 1. Max 5 tasks limit & default 1-hour (3600s) countdown
            let store = TodoStore(storageDirectoryURL: tempDir)
            for i in 1...5 {
                guard store.addTask(title: "Task \(i)") else {
                    print("FAIL: Could not add task \(i)")
                    return 1
                }
            }
            guard store.items.count == 5,
                  !store.canAddMore,
                  !store.addTask(title: "Task 6"),
                  store.items[0].configuredDurationSeconds == 3600,
                  store.items[0].remainingDurationSeconds == 3600 else {
                print("FAIL: Max 5 tasks limit or default 1h duration failed")
                return 1
            }

            // 2. Single Active Timer Rule, 1h Countdown & Accumulated Time
            let t0 = Date(timeIntervalSince1970: 1_700_000_000)
            let timerStore = TodoStore(storageDirectoryURL: tempDir.appendingPathComponent("timer"), now: t0)
            timerStore.addTask(title: "Task A", now: t0)
            timerStore.addTask(title: "Task B", now: t0)
            let idA = timerStore.items[0].id
            let idB = timerStore.items[1].id

            timerStore.toggleTimer(id: idA, now: t0)
            let t1 = t0.addingTimeInterval(95) // 1m 35s elapsed -> 58m 25s remaining
            timerStore.toggleTimer(id: idB, now: t1)

            guard !timerStore.items[0].isRunning,
                  timerStore.items[0].accumulatedSeconds == 95,
                  timerStore.items[0].remainingDurationSeconds == 3505,
                  timerStore.items[0].formattedRemainingString(at: t1) == "58:25",
                  timerStore.items[1].isRunning else {
                print("FAIL: Single active timer or countdown/accumulated calculation failed")
                return 1
            }

            // 3. Custom Duration Modification preserves accumulated time & auto-stops at 00:00
            timerStore.setTaskDuration(id: idA, minutes: 10, now: t1)
            guard timerStore.items[0].accumulatedSeconds == 95,
                  timerStore.items[0].remainingDurationSeconds == 600,
                  timerStore.items[0].formattedRemainingString(at: t1) == "10:00" else {
                print("FAIL: Custom duration modification did not preserve accumulated time")
                return 1
            }

            // Run Task A for 10m (600s) until 00:00 -> should auto-stop and mark didFinishCountdown
            timerStore.toggleTimer(id: idA, now: t1)
            let t2 = t1.addingTimeInterval(600)
            timerStore.handleTimerTick(now: t2)
            guard !timerStore.items[0].isRunning,
                  timerStore.items[0].didFinishCountdown,
                  timerStore.items[0].remainingDurationSeconds == 0,
                  timerStore.items[0].accumulatedSeconds == 695 else {
                print("FAIL: Auto-stop at 00:00 failed")
                return 1
            }

            // 4. Carry over incomplete tasks + accumulated time across days
            let carryDir = tempDir.appendingPathComponent("carry")
            let day1 = Date(timeIntervalSince1970: 1_700_000_000)
            let storeDay1 = TodoStore(storageDirectoryURL: carryDir, now: day1)
            storeDay1.addTask(title: "Completed Task", now: day1)
            storeDay1.addTask(title: "Carried Task", now: day1)
            storeDay1.toggleComplete(id: storeDay1.items[0].id, now: day1)
            storeDay1.toggleTimer(id: storeDay1.items[1].id, now: day1)
            storeDay1.toggleTimer(id: storeDay1.items[1].id, now: day1.addingTimeInterval(1800))

            let day2 = day1.addingTimeInterval(86_400)
            let storeDay2 = TodoStore(storageDirectoryURL: carryDir, now: day2)
            guard storeDay2.items.count == 1,
                  storeDay2.items[0].title == "Carried Task",
                  storeDay2.items[0].accumulatedSeconds == 1800,
                  storeDay2.items[0].remainingDurationSeconds == 1800 else {
                print("FAIL: Daily carryover of incomplete tasks + accumulated time failed")
                return 1
            }

            // 5. Obsidian Markdown export format uses accumulated time
            let mdDir = tempDir.appendingPathComponent("md")
            let mdStore = TodoStore(storageDirectoryURL: mdDir, now: t0)
            mdStore.addTask(title: "Task Title 1", durationMinutes: 90, now: t0)
            mdStore.addTask(title: "Task Title 2", durationMinutes: 60, now: t0)
            mdStore.toggleTimer(id: mdStore.items[0].id, now: t0)
            let tMd1 = t0.addingTimeInterval(4500) // 1h 15m
            mdStore.toggleComplete(id: mdStore.items[0].id, now: tMd1)
            mdStore.toggleTimer(id: mdStore.items[1].id, now: tMd1)
            let tMd2 = tMd1.addingTimeInterval(1920) // 0h 32m

            let expectedMD = "- [x] Task Title 1 (1h 15m)\n- [ ] Task Title 2 (0h 32m)"
            let actualMD = mdStore.generateMarkdown(now: tMd2)
            guard actualMD == expectedMD else {
                print("FAIL: Markdown mismatch:\n\(actualMD)")
                return 1
            }

            print("PASS: All 5 core specification test suites passed!")
            return 0
        } catch {
            print("FAIL: Unexpected error \(error)")
            return 1
        }
    }
}
