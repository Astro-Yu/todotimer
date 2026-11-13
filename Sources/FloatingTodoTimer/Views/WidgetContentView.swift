import AppKit
import SwiftUI

public struct WidgetContentView: View {
    @ObservedObject var store: TodoStore
    var onRequestTextFocus: () -> Void
    var onReleaseTextFocus: () -> Void

    @State private var newTaskTitle: String = ""
    @State private var editingTaskID: UUID? = nil
    @State private var editingTitleDraft: String = ""
    @State private var editingTimeTaskID: UUID? = nil
    @State private var editingMinutesDraft: String = "60"
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case addTask
        case editTask(UUID)
        case editMinutes(UUID)
    }

    // Deep, high-contrast dark blue for clear legibility against gray material backgrounds
    private let deepBlue = Color(red: 0.04, green: 0.23, blue: 0.62)
    private let deepOrange = Color(red: 0.80, green: 0.32, blue: 0.00)

    public init(
        store: TodoStore,
        onRequestTextFocus: @escaping () -> Void = {},
        onReleaseTextFocus: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onRequestTextFocus = onRequestTextFocus
        self.onReleaseTextFocus = onReleaseTextFocus
    }

    public var body: some View {
        let now = store.currentTime
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
                    )

                if store.isExpanded {
                    expandedView(now: now)
                        .frame(
                            width: geo.size.width,
                            height: FloatingPanelController.expandedSize.height,
                            alignment: .top
                        )
                        .transition(.opacity)
                } else {
                    compactView(now: now)
                        .frame(
                            width: geo.size.width,
                            height: FloatingPanelController.compactSize.height,
                            alignment: .center
                        )
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .animation(.easeOut(duration: 0.16), value: store.isExpanded)
        .onChange(of: store.isExpanded) { _, expanded in
            if !expanded {
                // If user was editing a title and moved the mouse out, save any non-empty change before closing
                if let editingID = editingTaskID {
                    let trimmed = editingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.updateTitle(id: editingID, newTitle: trimmed)
                    }
                }
                editingTaskID = nil
                editingTimeTaskID = nil
                focusedField = nil
                onReleaseTextFocus()
            }
        }
        .onChange(of: focusedField) { _, newValue in
            let isEditing = (newValue != nil)
            if store.isEditingText != isEditing {
                store.isEditingText = isEditing
            }
            if isEditing {
                onRequestTextFocus()
            } else {
                onReleaseTextFocus()
            }
        }
    }

    // MARK: - Compact Mode (300 x 44 px)

    @ViewBuilder
    private func compactView(now: Date) -> some View {
        HStack(spacing: 8) {
            if let display = store.compactDisplayTask {
                let item = display.item
                priorityBadge(priority: display.priority, isRunning: item.isRunning)

                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Remaining countdown time
                Text(item.formattedRemainingString(at: now))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        item.didFinishCountdown
                            ? deepOrange
                            : (item.isRunning ? deepBlue : .primary)
                    )

                Button {
                    store.toggleTimer(id: item.id)
                } label: {
                    Image(systemName: item.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(item.isRunning ? deepOrange : deepBlue)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help(item.isRunning ? "일시정지" : "타이머 시작")
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("마우스를 0.5초 올려 할 일 추가 (최대 5개)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: FloatingPanelController.compactSize.height)
    }

    // MARK: - Expanded Mode (300 x 280 px)

    @ViewBuilder
    private func expandedView(now: Date) -> some View {
        VStack(spacing: 0) {
            headerBar(now: now)

            Divider()
                .opacity(0.5)

            taskListSection(now: now)

            Divider()
                .opacity(0.5)

            footerAddTaskBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func headerBar(now: Date) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(store.activeRunningTask != nil ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text("TODOS (\(store.items.count)/\(TodoStore.maxItems))")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("· 누적 \(store.formattedTotalAccumulated(at: now))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.copyMarkdownToClipboard(now: now)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: store.showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(store.showCopiedFeedback ? "Copied!" : "Copy MD")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(store.showCopiedFeedback ? Color.green : .primary)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("Obsidian 마크다운으로 복사")

            Button {
                store.togglePinnedExpanded()
            } label: {
                Image(systemName: store.isPinnedExpanded ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.isPinnedExpanded ? deepBlue : .secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(store.isPinnedExpanded ? deepBlue.opacity(0.15) : Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("확장 화면 고정 토글 (Opt+Space)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func taskListSection(now: Date) -> some View {
        if store.items.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "timer")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text("등록된 할 일이 없습니다")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("아래 입력창에 할 일을 추가하세요 (기본 1시간 타이머)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        taskRow(index: index, item: item, now: now)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func taskRow(index: Int, item: TodoItem, now: Date) -> some View {
        let priority = index + 1
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                priorityBadge(priority: priority, isRunning: item.isRunning)

                // Completion Checkbox
                Button {
                    store.toggleComplete(id: item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isCompleted ? Color.green : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? "미완료로 변경" : "완료 체크")

                // Title + Accumulated Time sub-label
                VStack(alignment: .leading, spacing: 1) {
                    if editingTaskID == item.id {
                        HStack(spacing: 4) {
                            TextField("할 일 제목", text: $editingTitleDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.10))
                                )
                                .focused($focusedField, equals: .editTask(item.id))
                                .onAppear {
                                    onRequestTextFocus()
                                    DispatchQueue.main.async {
                                        focusedField = .editTask(item.id)
                                    }
                                }
                                .onSubmit {
                                    commitTitleEdit(for: item.id)
                                }
                                .onExitCommand {
                                    cancelTitleEdit()
                                }

                            Button {
                                commitTitleEdit(for: item.id)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.green)
                            }
                            .buttonStyle(.plain)
                            .help("제목 저장 (Enter)")
                        }
                    } else {
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(
                                TitleClickOverlay {
                                    beginTitleEditing(item: item)
                                }
                            )
                            .help("더블클릭 또는 우클릭하여 제목 수정")
                    }

                    HStack(spacing: 4) {
                        Text("누적 \(item.formattedAccumulatedBadge(at: now))")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if item.didFinishCountdown {
                            Text("· 타이머 종료")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(deepOrange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Priority Up/Down Controls
                VStack(spacing: 1) {
                    Button {
                        store.movePriority(id: item.id, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(index > 0 ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        store.movePriority(id: item.id, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(index < store.items.count - 1 ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= store.items.count - 1)
                }
                .frame(width: 11)

                // Clickable Remaining Countdown Time Badge (opens inline time editor)
                Button {
                    toggleTimeEditor(for: item, now: now)
                } label: {
                    Text(item.formattedRemainingString(at: now))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            item.didFinishCountdown
                                ? deepOrange
                                : (item.isRunning ? deepBlue : .primary)
                        )
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(editingTimeTaskID == item.id ? 0.16 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("클릭하여 타이머 시간 설정 (기본 60분)")

                // Play/Pause Button
                Button {
                    store.toggleTimer(id: item.id)
                } label: {
                    Image(systemName: item.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(item.isRunning ? deepOrange : deepBlue)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help(item.isRunning ? "일시정지" : "타이머 시작")

                // Delete Button
                Button {
                    if editingTaskID == item.id {
                        cancelTitleEdit()
                    }
                    if editingTimeTaskID == item.id {
                        editingTimeTaskID = nil
                    }
                    store.deleteTask(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("삭제")
            }

            // Inline Countdown Duration Editor (shown when clicking the remaining time badge)
            if editingTimeTaskID == item.id {
                inlineTimeEditorBar(for: item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(item.isRunning ? deepBlue.opacity(0.11) : Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private func inlineTimeEditorBar(for item: TodoItem) -> some View {
        HStack(spacing: 4) {
            Button("-10m") {
                store.adjustTaskRemainingTime(id: item.id, deltaMinutes: -10)
                syncMinutesDraft(for: item.id)
            }
            .buttonStyle(TimePresetButtonStyle())

            Button("-5m") {
                store.adjustTaskRemainingTime(id: item.id, deltaMinutes: -5)
                syncMinutesDraft(for: item.id)
            }
            .buttonStyle(TimePresetButtonStyle())

            Button("+5m") {
                store.adjustTaskRemainingTime(id: item.id, deltaMinutes: 5)
                syncMinutesDraft(for: item.id)
            }
            .buttonStyle(TimePresetButtonStyle())

            Button("+10m") {
                store.adjustTaskRemainingTime(id: item.id, deltaMinutes: 10)
                syncMinutesDraft(for: item.id)
            }
            .buttonStyle(TimePresetButtonStyle())

            Button("60m") {
                store.setTaskDuration(id: item.id, minutes: 60)
                editingMinutesDraft = "60"
            }
            .buttonStyle(TimePresetButtonStyle())

            Spacer(minLength: 2)

            HStack(spacing: 2) {
                TextField("분", text: $editingMinutesDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 28)
                    .focused($focusedField, equals: .editMinutes(item.id))
                    .onTapGesture {
                        onRequestTextFocus()
                        focusedField = .editMinutes(item.id)
                    }
                    .onSubmit {
                        commitMinutesEdit(for: item.id)
                    }
                Text("분")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )

            Button {
                commitMinutesEdit(for: item.id)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(deepBlue)
            }
            .buttonStyle(.plain)
            .help("시간 적용")
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func footerAddTaskBar() -> some View {
        if store.canAddMore {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(deepBlue)

                TextField("할 일 추가 (#\(store.items.count + 1), 기본 60분)...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .focused($focusedField, equals: .addTask)
                    .onTapGesture {
                        onRequestTextFocus()
                        focusedField = .addTask
                    }
                    .onSubmit {
                        submitNewTask()
                    }
                    .onExitCommand {
                        focusedField = nil
                        onReleaseTextFocus()
                    }

                if !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        submitNewTask()
                    } label: {
                        Text("추가")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(deepBlue)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("최대 5개 도달 — 기존 할 일을 먼저 완료하세요")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func priorityBadge(priority: Int, isRunning: Bool) -> some View {
        Text("#\(priority)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(isRunning ? .white : .primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isRunning ? deepBlue : Color.primary.opacity(0.14))
            )
    }

    private func submitNewTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if store.addTask(title: trimmed) {
            newTaskTitle = ""
            if !store.canAddMore {
                focusedField = nil
                onReleaseTextFocus()
            }
        }
    }

    private func beginTitleEditing(item: TodoItem) {
        editingTimeTaskID = nil
        editingTaskID = item.id
        editingTitleDraft = item.title
        onRequestTextFocus()
        DispatchQueue.main.async {
            focusedField = .editTask(item.id)
        }
    }

    private func commitTitleEdit(for id: UUID) {
        store.updateTitle(id: id, newTitle: editingTitleDraft)
        editingTaskID = nil
        editingTitleDraft = ""
        focusedField = nil
        onReleaseTextFocus()
    }

    private func cancelTitleEdit() {
        editingTaskID = nil
        editingTitleDraft = ""
        focusedField = nil
        onReleaseTextFocus()
    }

    private func toggleTimeEditor(for item: TodoItem, now: Date) {
        editingTaskID = nil
        if editingTimeTaskID == item.id {
            editingTimeTaskID = nil
            focusedField = nil
            onReleaseTextFocus()
        } else {
            editingTimeTaskID = item.id
            let currentMins = max(1, (item.currentRemainingSeconds(at: now) + 59) / 60)
            editingMinutesDraft = "\(currentMins)"
        }
    }

    private func syncMinutesDraft(for id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        let mins = max(1, (item.currentRemainingSeconds(at: store.currentTime) + 59) / 60)
        editingMinutesDraft = "\(mins)"
    }

    private func commitMinutesEdit(for id: UUID) {
        let digits = editingMinutesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mins = Int(digits), mins > 0 {
            store.setTaskDuration(id: id, minutes: mins)
        }
        editingTimeTaskID = nil
        focusedField = nil
        onReleaseTextFocus()
    }
}

private struct TimePresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.08))
            )
    }
}

/// AppKit NSView overlay that reliably captures both double-click (`clickCount == 2`) and
/// right-click (`rightMouseDown`) on the task title without being swallowed by NSPanel window dragging.
private struct TitleClickOverlay: NSViewRepresentable {
    let onActivateEdit: () -> Void

    func makeNSView(context: Context) -> TitleClickNSView {
        let view = TitleClickNSView()
        view.onActivateEdit = onActivateEdit
        return view
    }

    func updateNSView(_ nsView: TitleClickNSView, context: Context) {
        nsView.onActivateEdit = onActivateEdit
    }

    final class TitleClickNSView: NSView {
        var onActivateEdit: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                onActivateEdit?()
            } else {
                super.mouseDown(with: event)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onActivateEdit?()
        }
    }
}
