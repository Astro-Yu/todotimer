import AppKit
import Combine
import Foundation

@MainActor
public final class TodoStore: ObservableObject {
    public static let maxItems = 5

    @Published public private(set) var items: [TodoItem] = []
    @Published public var isHovered: Bool = false
    @Published public var isPinnedExpanded: Bool = false
    @Published public var isEditingText: Bool = false
    @Published public var showCopiedFeedback: Bool = false
    @Published public private(set) var currentTime: Date = Date()

    private let storageDirectoryURL: URL
    private let fileManager: FileManager
    private var currentLoadedDateString: String = ""
    private var feedbackTask: Task<Void, Never>?
    private var tickTimer: Timer?

    public var isExpanded: Bool {
        isHovered || isPinnedExpanded
    }

    public var canAddMore: Bool {
        items.count < Self.maxItems
    }

    public var activeRunningTask: (priority: Int, item: TodoItem)? {
        guard let index = items.firstIndex(where: { $0.isRunning }) else {
            return nil
        }
        return (index + 1, items[index])
    }

    /// Returns the task to display in Compact Mode:
    /// 1. Currently running task (if any)
    /// 2. Highest-priority incomplete task
    /// 3. Fallback to #1 task if all tasks are completed
    public var compactDisplayTask: (priority: Int, item: TodoItem)? {
        if let running = activeRunningTask {
            return running
        }
        if let firstIncompleteIndex = items.firstIndex(where: { !$0.isCompleted }) {
            return (firstIncompleteIndex + 1, items[firstIncompleteIndex])
        }
        if let first = items.first {
            return (1, first)
        }
        return nil
    }

    public func totalAccumulatedSeconds(at now: Date = Date()) -> Int {
        items.reduce(0) { $0 + $1.totalElapsedSeconds(at: now) }
    }

    public func formattedTotalAccumulated(at now: Date = Date()) -> String {
        let total = totalAccumulatedSeconds(at: now)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    public init(
        storageDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) {
        self.fileManager = fileManager
        self.currentTime = now
        if let customURL = storageDirectoryURL {
            self.storageDirectoryURL = customURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.storageDirectoryURL = appSupport.appendingPathComponent("FloatingTodoTimer", isDirectory: true)
        }
        load(now: now)
        updateTickTimerState()
    }

    // MARK: - Task Management

    @discardableResult
    public func addTask(title: String, durationMinutes: Int = 60, now: Date = Date()) -> Bool {
        checkDayRolloverIfNeeded(now: now)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, items.count < Self.maxItems else {
            return false
        }
        let durationSeconds = max(60, durationMinutes * 60)
        let newItem = TodoItem(
            title: trimmed,
            configuredDurationSeconds: durationSeconds,
            remainingDurationSeconds: durationSeconds
        )
        items.append(newItem)
        save(now: now)
        return true
    }

    public func toggleComplete(id: UUID, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()

        // If marked completed while running, automatically pause the timer
        if items[index].isCompleted && items[index].isRunning {
            pauseTask(at: index, now: now)
        }
        updateTickTimerState()
        save(now: now)
    }

    public func updateTitle(id: UUID, newTitle: String, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
        save(now: now)
    }

    public func deleteTask(id: UUID, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        items.removeAll { $0.id == id }
        updateTickTimerState()
        save(now: now)
    }

    public func moveTasks(fromOffsets source: IndexSet, toOffset destination: Int, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        items.move(fromOffsets: source, toOffset: destination)
        save(now: now)
    }

    public func movePriority(id: UUID, direction: Int, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard targetIndex >= 0 && targetIndex < items.count else { return }
        items.swapAt(index, targetIndex)
        save(now: now)
    }

    // MARK: - Countdown Time Customization

    /// Sets the task's countdown duration (in minutes) while preserving accumulated time.
    public func setTaskDuration(id: UUID, minutes: Int, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let clampedMinutes = min(max(1, minutes), 999)
        let seconds = clampedMinutes * 60

        if items[index].isRunning {
            items[index].accumulatedSeconds = items[index].totalElapsedSeconds(at: now)
            items[index].lastResumedAt = now
        }
        items[index].configuredDurationSeconds = seconds
        items[index].remainingDurationSeconds = seconds
        items[index].didFinishCountdown = false
        currentTime = now
        save(now: now)
    }

    /// Adjusts the task's current remaining countdown by `deltaMinutes` (e.g. -10, +10) while preserving accumulated time.
    public func adjustTaskRemainingTime(id: UUID, deltaMinutes: Int, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let currentRem = items[index].currentRemainingSeconds(at: now)
        let newRemaining = min(max(60, currentRem + (deltaMinutes * 60)), 999 * 60)

        if items[index].isRunning {
            items[index].accumulatedSeconds = items[index].totalElapsedSeconds(at: now)
            items[index].lastResumedAt = now
        }
        items[index].remainingDurationSeconds = newRemaining
        items[index].configuredDurationSeconds = newRemaining
        items[index].didFinishCountdown = false
        currentTime = now
        save(now: now)
    }

    // MARK: - Exclusive Per-Task Timer

    public func toggleTimer(id: UUID, now: Date = Date()) {
        checkDayRolloverIfNeeded(now: now)
        guard let targetIndex = items.firstIndex(where: { $0.id == id }) else { return }

        if items[targetIndex].isRunning {
            pauseTask(at: targetIndex, now: now)
        } else {
            // Single Active Timer Rule: pause any other running task first
            for idx in items.indices where idx != targetIndex && items[idx].isRunning {
                pauseTask(at: idx, now: now)
            }
            // If countdown had reached 00:00, reset remaining countdown to configured duration (default 1h)
            if items[targetIndex].remainingDurationSeconds <= 0 {
                items[targetIndex].remainingDurationSeconds = max(60, items[targetIndex].configuredDurationSeconds)
            }
            items[targetIndex].didFinishCountdown = false
            items[targetIndex].lastResumedAt = now
        }
        currentTime = now
        updateTickTimerState()
        save(now: now)
    }

    public func pauseAllTimers(now: Date = Date()) {
        var modified = false
        for idx in items.indices where items[idx].isRunning {
            pauseTask(at: idx, now: now)
            modified = true
        }
        updateTickTimerState()
        if modified {
            save(now: now)
        }
    }

    private func pauseTask(at index: Int, now: Date) {
        let sessionElapsed = items[index].currentSessionElapsedSeconds(at: now)
        let remaining = items[index].currentRemainingSeconds(at: now)
        items[index].accumulatedSeconds += sessionElapsed
        items[index].remainingDurationSeconds = remaining
        items[index].lastResumedAt = nil
    }

    // MARK: - Live Tick & Auto-Stop at 00:00

    private func updateTickTimerState() {
        let anyRunning = items.contains(where: { $0.isRunning })
        if anyRunning {
            guard tickTimer == nil else { return }
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleTimerTick()
                }
            }
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    public func handleTimerTick(now: Date = Date()) {
        currentTime = now
        var finishedAny = false

        for idx in items.indices where items[idx].isRunning {
            if items[idx].currentRemainingSeconds(at: now) <= 0 {
                pauseTask(at: idx, now: now)
                items[idx].remainingDurationSeconds = 0
                items[idx].didFinishCountdown = true
                finishedAny = true
            }
        }

        if finishedAny {
            updateTickTimerState()
            save(now: now)
            playCompletionSound()
        }
    }

    private func playCompletionSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Hotkey / UI State

    public func togglePinnedExpanded() {
        isPinnedExpanded.toggle()
    }

    // MARK: - Markdown Export

    public func generateMarkdown(now: Date = Date()) -> String {
        items.map { $0.formattedMarkdownLine(at: now) }.joined(separator: "\n")
    }

    public func copyMarkdownToClipboard(now: Date = Date()) {
        let markdown = generateMarkdown(now: now)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)

        showCopiedFeedback = true
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                self.showCopiedFeedback = false
            }
        }
    }

    // MARK: - Persistence (~/Library/Application Support/FloatingTodoTimer/YYYY-MM-DD.json)

    public static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public func fileURL(for date: Date) -> URL {
        let filename = "\(Self.dateString(for: date)).json"
        return storageDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    public func load(now: Date = Date()) {
        ensureDirectoryExists()
        let todayKey = Self.dateString(for: now)
        currentLoadedDateString = todayKey
        let todayURL = fileURL(for: now)

        if fileManager.fileExists(atPath: todayURL.path) {
            if let loaded = decodeItems(from: todayURL) {
                self.items = Array(loaded.prefix(Self.maxItems))
                handleTimerTick(now: now)
                return
            }
        }

        // Today's file does not exist yet: check for most recent previous day's file
        // and carry over incomplete tasks along with their accumulated time.
        if let previousURL = mostRecentPreviousFileURL(before: todayKey),
           let previousItems = decodeItems(from: previousURL) {
            let carriedOver = previousItems
                .filter { !$0.isCompleted }
                .prefix(Self.maxItems)
                .map { item -> TodoItem in
                    var copy = item
                    if copy.isRunning {
                        let sessionElapsed = copy.currentSessionElapsedSeconds(at: now)
                        let remaining = copy.currentRemainingSeconds(at: now)
                        copy.accumulatedSeconds += sessionElapsed
                        copy.remainingDurationSeconds = remaining
                        if remaining <= 0 {
                            copy.lastResumedAt = nil
                            copy.didFinishCountdown = true
                        } else {
                            copy.lastResumedAt = now
                        }
                    }
                    return copy
                }
            self.items = Array(carriedOver)
        } else {
            self.items = []
        }

        save(now: now)
    }

    public func save(now: Date = Date()) {
        ensureDirectoryExists()
        let url = fileURL(for: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[FloatingTodoTimer] Failed to save todos to \(url.path): \(error)")
        }
    }

    public func checkDayRolloverIfNeeded(now: Date = Date()) {
        let todayKey = Self.dateString(for: now)
        guard !currentLoadedDateString.isEmpty, todayKey != currentLoadedDateString else {
            return
        }
        if let previousDate = Self.parseDateString(currentLoadedDateString) {
            save(now: previousDate)
        }
        currentLoadedDateString = todayKey
        items = items.filter { !$0.isCompleted }
        save(now: now)
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: storageDirectoryURL.path) {
            try? fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func decodeItems(from url: URL) -> [TodoItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([TodoItem].self, from: data)
    }

    private func mostRecentPreviousFileURL(before todayKey: String) -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storageDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let datePattern = #"^\d{4}-\d{2}-\d{2}\.json$"#
        let previousFiles = urls.filter { url in
            let name = url.lastPathComponent
            guard name.range(of: datePattern, options: .regularExpression) != nil else {
                return false
            }
            let stem = String(name.dropLast(5))
            return stem < todayKey
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return previousFiles.last
    }

    private static func parseDateString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
