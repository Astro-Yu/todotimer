import Foundation

public struct TodoItem: Identifiable, Codable, Equatable {
    public static let defaultDurationSeconds = 3600 // 1 hour (60 minutes)

    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    /// Total elapsed seconds accumulated across all work sessions prior to the current active run.
    public var accumulatedSeconds: Int
    /// User-configured countdown duration in seconds (default: 3600 = 1 hour).
    public var configuredDurationSeconds: Int
    /// Remaining countdown seconds as of the start of the current run (or when paused).
    public var remainingDurationSeconds: Int
    /// Non-nil when this task's countdown timer is actively running.
    public var lastResumedAt: Date?
    /// True when the most recent countdown reached 00:00 naturally.
    public var didFinishCountdown: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        accumulatedSeconds: Int = 0,
        configuredDurationSeconds: Int = TodoItem.defaultDurationSeconds,
        remainingDurationSeconds: Int? = nil,
        lastResumedAt: Date? = nil,
        didFinishCountdown: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.accumulatedSeconds = accumulatedSeconds
        self.configuredDurationSeconds = max(60, configuredDurationSeconds)
        self.remainingDurationSeconds = remainingDurationSeconds ?? max(60, configuredDurationSeconds)
        self.lastResumedAt = lastResumedAt
        self.didFinishCountdown = didFinishCountdown
    }

    // Backward-compatible decoding for JSON files saved before countdown fields were added
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case accumulatedSeconds
        case configuredDurationSeconds
        case remainingDurationSeconds
        case lastResumedAt
        case didFinishCountdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.accumulatedSeconds = try container.decodeIfPresent(Int.self, forKey: .accumulatedSeconds) ?? 0
        let configured = try container.decodeIfPresent(Int.self, forKey: .configuredDurationSeconds)
            ?? Self.defaultDurationSeconds
        self.configuredDurationSeconds = max(60, configured)
        self.remainingDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingDurationSeconds)
            ?? self.configuredDurationSeconds
        self.lastResumedAt = try container.decodeIfPresent(Date.self, forKey: .lastResumedAt)
        self.didFinishCountdown = try container.decodeIfPresent(Bool.self, forKey: .didFinishCountdown) ?? false
    }

    public var isRunning: Bool {
        lastResumedAt != nil
    }

    /// Elapsed seconds in the current active run session, capped by `remainingDurationSeconds`.
    public func currentSessionElapsedSeconds(at now: Date = Date()) -> Int {
        guard let lastResumedAt else { return 0 }
        let rawDelta = max(0, Int(now.timeIntervalSince(lastResumedAt)))
        return min(rawDelta, max(0, remainingDurationSeconds))
    }

    /// Remaining countdown seconds at `now`.
    public func currentRemainingSeconds(at now: Date = Date()) -> Int {
        guard let lastResumedAt else {
            return max(0, remainingDurationSeconds)
        }
        let rawDelta = max(0, Int(now.timeIntervalSince(lastResumedAt)))
        return max(0, remainingDurationSeconds - rawDelta)
    }

    /// Total accumulated seconds spent on this task (including active session progress).
    public func totalElapsedSeconds(at now: Date = Date()) -> Int {
        max(0, accumulatedSeconds + currentSessionElapsedSeconds(at: now))
    }

    /// Formats remaining countdown time as `MM:SS` (under 1h) or `HH:MM:SS` (1h+).
    public func formattedRemainingString(at now: Date = Date()) -> String {
        Self.formatClock(seconds: currentRemainingSeconds(at: now))
    }

    /// Formats total accumulated time as `MM:SS` or `HH:MM:SS`.
    public func formattedTimerString(at now: Date = Date()) -> String {
        Self.formatClock(seconds: totalElapsedSeconds(at: now))
    }

    /// Formats total accumulated time for the Expanded view badge (e.g. `1h 15m` or `12m 30s`).
    public func formattedAccumulatedBadge(at now: Date = Date()) -> String {
        let total = totalElapsedSeconds(at: now)
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

    /// Formats elapsed time for Obsidian Markdown export as `(Xh Ym)`.
    public func formattedMarkdownLine(at now: Date = Date()) -> String {
        let total = totalElapsedSeconds(at: now)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let checkbox = isCompleted ? "[x]" : "[ ]"
        return "- \(checkbox) \(title) (\(hours)h \(minutes)m)"
    }

    public static func formatClock(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
