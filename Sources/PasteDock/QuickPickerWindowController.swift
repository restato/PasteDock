import AppKit
import ClipboardCore
import Foundation
import SwiftUI

enum BarPanelTab: String, CaseIterable {
    case quick
    case settings

    var title: String {
        switch self {
        case .quick:
            return "Clipboard"
        case .settings:
            return "Settings"
        }
    }
}

@MainActor
final class BarPopoverState: ObservableObject {
    @Published var currentTab: BarPanelTab = .quick
    @Published var isPresented: Bool = false
    @Published var focusQuickSearchToken = UUID()
    @Published var glassCapability: GlassCapability = LiquidGlassSupport.currentCapability()

    func requestQuickSearchFocus() {
        focusQuickSearchToken = UUID()
    }

    func refreshGlassCapability() {
        glassCapability = LiquidGlassSupport.currentCapability()
    }
}

@MainActor
final class BarPopoverController: NSObject {
    private let model: QuickPickerPanelModel
    private let coordinator: AppCoordinator
    private let state = BarPopoverState()

    private var popover: NSPopover?
    private weak var statusBarButton: NSStatusBarButton?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var indexInputBuffer: String = ""
    private var indexInputTimer: Timer?
    private let indexInputCommitDelay: TimeInterval = 0.35

    var isPresented: Bool {
        state.isPresented
    }

    init(model: QuickPickerPanelModel, coordinator: AppCoordinator) {
        self.model = model
        self.coordinator = coordinator
        super.init()
    }

    func bindStatusBarButton(_ button: NSStatusBarButton?) {
        statusBarButton = button
    }

    func present(tab: BarPanelTab, focusSearch: Bool) {
        guard let statusBarButton else {
            NSLog("[BarPopoverController] status bar button is unavailable; skipping panel presentation")
            return
        }

        if popover == nil {
            popover = buildPopover()
        }

        guard let popover else { return }

        state.refreshGlassCapability()
        state.currentTab = tab
        state.isPresented = true

        if tab == .quick {
            model.refresh()
            model.ensureInitialSelection()
            if focusSearch {
                state.requestQuickSearchFocus()
            }
        }

        if !popover.isShown {
            popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: .minY)
            installKeyMonitorIfNeeded()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        popover?.performClose(nil)
        cleanupPresentationState()
    }

    private func buildPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 900, height: 470)
        popover.contentViewController = NSHostingController(
            rootView: BarPanelRootView(
                state: state,
                model: model,
                coordinator: coordinator,
                sourceAppIconProvider: { [coordinator] bundleId in
                    coordinator.resolveSourceAppIcon(bundleId: bundleId)
                },
                onSwitchToQuick: { [weak self] in
                    guard let self else { return }
                    self.present(tab: .quick, focusSearch: true)
                }
            )
        )
        return popover
    }

    private func installKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover?.isShown == true else { return event }
            return self.handle(event: event) ? nil : event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.popover?.isShown == true else { return event }
            return self.handleMouse(event: event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func cleanupPresentationState() {
        removeKeyMonitor()
        resetIndexInput()
        model.hoveredEntryID = nil
        model.previewSelectedFilePath = nil
        state.isPresented = false
    }

    private func handle(event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        if keyCode == 53 { // Esc
            dismiss()
            return true
        }

        if keyCode == 48 { // Tab
            resetIndexInput()
            if state.currentTab == .quick {
                state.currentTab = .settings
            } else {
                state.currentTab = .quick
                model.refresh()
                model.ensureInitialSelection()
                state.requestQuickSearchFocus()
            }
            return true
        }

        guard state.currentTab == .quick else {
            return false
        }

        let isCommand = event.modifierFlags.contains(.command)

        if let chars = event.charactersIgnoringModifiers, chars.count == 1, let num = Int(chars), (0...9).contains(num) {
            handleIndexDigit(num)
            return true
        }

        if keyCode == 36 { // Enter
            if commitIndexInputIfPossible() {
                return true
            }
            model.executeSelectionOrTop()
            return true
        }

        if keyCode == 125 { // Arrow Down
            resetIndexInput()
            model.moveSelection(delta: 1)
            return true
        }

        if keyCode == 126 { // Arrow Up
            resetIndexInput()
            model.moveSelection(delta: -1)
            return true
        }

        if isCommand, keyCode == 51 { // Cmd+Backspace
            resetIndexInput()
            model.deleteSelection()
            return true
        }

        return false
    }

    private func handleMouse(event: NSEvent) -> Bool {
        guard state.currentTab == .quick else {
            return false
        }

        let isSecondaryClick = event.type == .rightMouseDown
        let isControlPrimaryClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        guard isSecondaryClick || isControlPrimaryClick else {
            return false
        }

        return model.selectHoveredEntryOnly(clearHover: true)
    }

    private func handleIndexDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if indexInputBuffer.isEmpty, digit == 0 {
            return
        }

        if indexInputBuffer.isEmpty {
            indexInputBuffer = "\(digit)"
        } else {
            indexInputBuffer += "\(digit)"
        }

        model.indexInputPreview = indexInputBuffer
        scheduleIndexInputCommit()

        guard let index = Int(indexInputBuffer), index >= 1 else {
            return
        }

        let maxIndex = model.entries.count
        guard maxIndex > 0 else { return }

        if index <= maxIndex, !hasLongerMatch(prefix: indexInputBuffer, maxIndex: maxIndex) {
            model.executeIndex(index - 1)
            resetIndexInput()
            return
        }

        if !hasAnyMatch(prefix: indexInputBuffer, maxIndex: maxIndex) {
            resetIndexInput()
        }
    }

    private func scheduleIndexInputCommit() {
        indexInputTimer?.invalidate()
        indexInputTimer = Timer.scheduledTimer(withTimeInterval: indexInputCommitDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                _ = self.commitIndexInputIfPossible()
            }
        }
    }

    @discardableResult
    private func commitIndexInputIfPossible() -> Bool {
        defer { resetIndexInput() }
        guard let index = Int(indexInputBuffer), index >= 1 else {
            return false
        }
        guard model.entries.indices.contains(index - 1) else {
            return false
        }
        model.executeIndex(index - 1)
        return true
    }

    private func resetIndexInput() {
        indexInputTimer?.invalidate()
        indexInputTimer = nil
        indexInputBuffer = ""
        model.indexInputPreview = ""
    }

    private func hasAnyMatch(prefix: String, maxIndex: Int) -> Bool {
        guard !prefix.isEmpty else { return false }
        for value in 1 ... maxIndex where String(value).hasPrefix(prefix) {
            return true
        }
        return false
    }

    private func hasLongerMatch(prefix: String, maxIndex: Int) -> Bool {
        guard !prefix.isEmpty else { return false }
        for value in 1 ... maxIndex {
            let text = String(value)
            if text.hasPrefix(prefix), text.count > prefix.count {
                return true
            }
        }
        return false
    }
}

extension BarPopoverController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cleanupPresentationState()
        }
    }
}

@MainActor
final class QuickPickerPanelModel: ObservableObject {
    @Published var query: String = "" {
        didSet { refresh() }
    }
    @Published var entries: [QuickPickerEntry] = []
    @Published var selectedEntryID: UUID?
    @Published var indexInputPreview: String = ""
    @Published var hoveredEntryID: UUID?
    @Published var previewSelectedFilePath: String?

    private let entryProvider: (String) -> [QuickPickerEntry]
    private let onExecuteIndex: (Int) -> Void
    private let onExecuteTop: () -> Void
    private let onDeleteSelection: (UUID) -> Void
    private let onClose: () -> Void

    init(
        entryProvider: @escaping (String) -> [QuickPickerEntry],
        onExecuteIndex: @escaping (Int) -> Void,
        onExecuteTop: @escaping () -> Void,
        onDeleteSelection: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.entryProvider = entryProvider
        self.onExecuteIndex = onExecuteIndex
        self.onExecuteTop = onExecuteTop
        self.onDeleteSelection = onDeleteSelection
        self.onClose = onClose
    }

    func refresh() {
        entries = entryProvider(query)

        if let hoveredEntryID,
           !entries.contains(where: { $0.id == hoveredEntryID })
        {
            self.hoveredEntryID = nil
        }

        if let selectedEntryID, let currentIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = entries[currentIndex].id
        } else {
            ensureInitialSelection()
        }
    }

    func selectOnlyIndex(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedEntryID = entries[index].id
    }

    func executeIndex(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedEntryID = entries[index].id
        onExecuteIndex(index)
    }

    @discardableResult
    func selectHoveredEntryOnly(clearHover: Bool = false) -> Bool {
        guard let hoveredEntryID else { return false }
        guard entries.contains(where: { $0.id == hoveredEntryID }) else { return false }
        selectedEntryID = hoveredEntryID
        if clearHover {
            self.hoveredEntryID = nil
        }
        return true
    }

    func executeTopResult() {
        onExecuteTop()
    }

    func executeSelectionOrTop() {
        if let selectedEntryID, let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) {
            executeIndex(selectedIndex)
            return
        }
        onExecuteTop()
    }

    func deleteSelection() {
        if let selectedEntryID {
            onDeleteSelection(selectedEntryID)
            return
        }
        guard let first = entries.first else { return }
        onDeleteSelection(first.id)
    }

    func close() {
        onClose()
    }

    func ensureInitialSelection() {
        guard selectedEntryID == nil else { return }
        selectedEntryID = entries.first?.id
    }

    func moveSelection(delta: Int) {
        guard !entries.isEmpty else { return }

        let currentIndex: Int
        if let selectedEntryID, let idx = entries.firstIndex(where: { $0.id == selectedEntryID }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }

        let next = max(0, min(entries.count - 1, currentIndex + delta))
        hoveredEntryID = nil
        selectedEntryID = entries[next].id
    }
}

private enum QuickPreviewKind {
    case none
    case text
    case image
    case file
}

private struct QuickTextPreview {
    let text: String
    let characterCount: Int
    let lineCount: Int
    let truncated: Bool
}

private struct QuickImagePreview {
    let payloadPath: String
    let image: NSImage
}

private struct QuickPreviewFileItem: Identifiable {
    let path: String
    let name: String
    let exists: Bool

    var id: String { path }
}

private struct QuickPreviewFileMetadata {
    let name: String
    let path: String
    let exists: Bool
    let sizeText: String
    let modifiedText: String
}

private struct QuickFilePreview {
    let files: [QuickPreviewFileItem]
    let selectedPath: String
    let selectedMetadata: QuickPreviewFileMetadata
}

private enum QuickPreviewContent {
    case none
    case text(QuickTextPreview)
    case image(QuickImagePreview)
    case file(QuickFilePreview)
    case unavailable(kind: QuickPreviewKind, message: String)

    var kind: QuickPreviewKind {
        switch self {
        case .none:
            return .none
        case .text:
            return .text
        case .image:
            return .image
        case .file:
            return .file
        case let .unavailable(kind, _):
            return kind
        }
    }
}

private struct QuickPreviewResolver {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private let byteCountFormatter: ByteCountFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        self.dateFormatter = dateFormatter

        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        self.byteCountFormatter = byteCountFormatter
    }

    func resolve(entry: QuickPickerEntry?, selectedFilePath: String?) -> QuickPreviewContent {
        guard let entry else {
            return .none
        }

        switch entry.kind {
        case .text:
            return resolveTextPreview(entry)
        case .image:
            return resolveImagePreview(entry)
        case .file:
            return resolveFilePreview(entry, selectedFilePath: selectedFilePath)
        }
    }

    private func resolveTextPreview(_ entry: QuickPickerEntry) -> QuickPreviewContent {
        guard let payloadPath = entry.payloadPath, !payloadPath.isEmpty else {
            return .unavailable(kind: .text, message: "Preview unavailable")
        }

        let url = URL(fileURLWithPath: payloadPath)
        guard let data = try? Data(contentsOf: url) else {
            return .unavailable(kind: .text, message: "Preview unavailable")
        }

        let fullText = String(decoding: data, as: UTF8.self)
        let byteLimitedData = data.count > 8_192 ? Data(data.prefix(8_192)) : data
        var previewText = String(decoding: byteLimitedData, as: UTF8.self)
        if previewText.count > 3_000 {
            previewText = String(previewText.prefix(3_000))
        }

        let truncated = data.count > 8_192 || fullText.count > previewText.count
        let lineCount = max(1, fullText.split(whereSeparator: \Character.isNewline).count)

        return .text(
            QuickTextPreview(
                text: previewText,
                characterCount: fullText.count,
                lineCount: lineCount,
                truncated: truncated
            )
        )
    }

    private func resolveImagePreview(_ entry: QuickPickerEntry) -> QuickPreviewContent {
        guard let payloadPath = entry.payloadPath, !payloadPath.isEmpty else {
            return .unavailable(kind: .image, message: "Preview unavailable")
        }

        guard let image = NSImage(contentsOfFile: payloadPath) else {
            return .unavailable(kind: .image, message: "Preview unavailable")
        }

        return .image(QuickImagePreview(payloadPath: payloadPath, image: image))
    }

    private func resolveFilePreview(_ entry: QuickPickerEntry, selectedFilePath: String?) -> QuickPreviewContent {
        guard let payloadPath = entry.payloadPath, !payloadPath.isEmpty else {
            return .unavailable(kind: .file, message: "Preview unavailable")
        }

        let payloadURL = URL(fileURLWithPath: payloadPath)
        guard
            let data = try? Data(contentsOf: payloadURL),
            let payload = try? JSONDecoder().decode(FileClipboardPayload.self, from: data),
            !payload.paths.isEmpty
        else {
            return .unavailable(kind: .file, message: "Preview unavailable")
        }

        let files = payload.paths.map { path in
            QuickPreviewFileItem(
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                exists: fileManager.fileExists(atPath: path)
            )
        }

        let selectedPath: String
        if let selectedFilePath, files.contains(where: { $0.path == selectedFilePath }) {
            selectedPath = selectedFilePath
        } else {
            selectedPath = files[0].path
        }

        let metadata = makeFileMetadata(for: selectedPath)
        return .file(
            QuickFilePreview(
                files: files,
                selectedPath: selectedPath,
                selectedMetadata: metadata
            )
        )
    }

    private func makeFileMetadata(for path: String) -> QuickPreviewFileMetadata {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let exists = fileManager.fileExists(atPath: path)

        guard exists else {
            return QuickPreviewFileMetadata(
                name: name,
                path: path,
                exists: false,
                sizeText: "Missing",
                modifiedText: "Missing"
            )
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes?[.modificationDate] as? Date

        return QuickPreviewFileMetadata(
            name: name,
            path: path,
            exists: true,
            sizeText: byteCountFormatter.string(fromByteCount: size),
            modifiedText: modifiedAt.map { dateFormatter.string(from: $0) } ?? "-"
        )
    }
}

private struct BarPanelRootView: View {
    @ObservedObject var state: BarPopoverState
    @ObservedObject var model: QuickPickerPanelModel
    @ObservedObject var coordinator: AppCoordinator
    let sourceAppIconProvider: (String?) -> NSImage?
    let onSwitchToQuick: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $state.currentTab) {
                ForEach(BarPanelTab.allCases, id: \.rawValue) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Panels")

            if state.currentTab == .quick {
                QuickTabView(
                    model: model,
                    state: state,
                    glassCapability: state.glassCapability,
                    sourceAppIconProvider: sourceAppIconProvider
                )
            } else {
                SettingsTabView(
                    coordinator: coordinator,
                    onOpenQuick: onSwitchToQuick,
                    glassCapability: state.glassCapability
                )
            }
        }
        .padding(8)
        .frame(minWidth: 840, minHeight: 420, alignment: .topLeading)
        .sheet(isPresented: $coordinator.accessibilityGuidePresented) {
            AccessibilitySetupGuideView(coordinator: coordinator, glassCapability: state.glassCapability)
        }
        .glassContainerStyle(state.glassCapability)
    }
}

private struct QuickTabView: View {
    @ObservedObject var model: QuickPickerPanelModel
    @ObservedObject var state: BarPopoverState
    let glassCapability: GlassCapability
    let sourceAppIconProvider: (String?) -> NSImage?

    @FocusState private var isSearchFocused: Bool
    @State private var previewContent: QuickPreviewContent = .none
    @State private var rowStatuses: [UUID: QuickEntryStatus] = [:]

    private let previewPanelWidth: CGFloat = 260
    private let previewResolver = QuickPreviewResolver()
    private let entryStatusResolver = QuickEntryStatusResolver()
    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)

            HStack(spacing: 10) {
                listView
                    .glassCardStyle(glassCapability)
                Divider()
                previewView
                    .glassCardStyle(glassCapability)
                    .frame(width: previewPanelWidth)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("↑/↓ Move   Enter Paste   1-9 Instant   Cmd+⌫ Delete   Tab Settings")
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !model.indexInputPreview.isEmpty {
                    Text("Index \(model.indexInputPreview)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassStatusStyle(glassCapability, kind: .neutral)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            refreshRowStatuses()
            updatePreviewContent()
            requestFocusIfNeeded()
        }
        .onChange(of: model.entries) { _, _ in
            refreshRowStatuses()
            updatePreviewContent()
        }
        .onChange(of: state.focusQuickSearchToken) { _, _ in
            requestFocusIfNeeded()
        }
        .onChange(of: state.currentTab) { _, _ in
            requestFocusIfNeeded()
            updatePreviewContent()
        }
        .onChange(of: model.hoveredEntryID) { _, _ in
            updatePreviewContent()
        }
        .onChange(of: model.selectedEntryID) { _, _ in
            updatePreviewContent()
        }
        .onChange(of: model.previewSelectedFilePath) { _, _ in
            updatePreviewContent()
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            listHeaderView
            Divider()
            List(selection: $model.selectedEntryID) {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    row(index: index, entry: entry)
                        .tag(entry.id)
                        .onTapGesture(count: 2) {
                            model.executeIndex(index)
                        }
                        .onTapGesture {
                            model.selectOnlyIndex(index)
                        }
                        .onHover { hovering in
                            if hovering {
                                model.hoveredEntryID = entry.id
                            } else if model.hoveredEntryID == entry.id {
                                model.hoveredEntryID = nil
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var listHeaderView: some View {
        HStack(spacing: 8) {
            Text("#")
                .frame(width: 30, alignment: .trailing)

            Text("Preview")
                .frame(width: 52, alignment: .leading)

            Text("Content")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Source")
                .frame(width: 130, alignment: .leading)

            Text("Time")
                .frame(width: 132, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func row(index: Int, entry: QuickPickerEntry) -> some View {
        let isMissing = rowStatus(for: entry).isMissing

        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle((1 ... 9).contains(index + 1) ? .secondary : .tertiary)

            thumbnail(for: entry)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayText)
                    .lineLimit(1)
                    .strikethrough(isMissing)
                    .foregroundStyle(isMissing ? Color.secondary : Color.primary)

                if isMissing {
                    Text("missing source file")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sourceView(for: entry)
                .frame(width: 130, alignment: .leading)

            Text(timeCaption(for: entry))
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isMissing ? 8 : 7)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(isMissing ? .hidden : .visible)
    }

    @ViewBuilder
    private func thumbnail(for entry: QuickPickerEntry) -> some View {
        switch entry.kind {
        case .text:
            QuickPickerTextThumbnail(glassCapability: glassCapability, size: 24)
        case .image:
            QuickPickerImageThumbnail(
                payloadPath: entry.payloadPath,
                glassCapability: glassCapability,
                size: 24
            )
        case .file:
            QuickPickerFileThumbnail(
                isMultipleFiles: entry.displayText.hasPrefix("[Files "),
                glassCapability: glassCapability,
                size: 24
            )
        }
    }

    @ViewBuilder
    private var previewView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(previewSelectionTitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(previewSelectionTitle)
            }
            Divider()

            Group {
                switch previewContent {
                case .none:
                    placeholderPreview(icon: "doc.text", message: "Select an item to preview")

                case let .unavailable(_, message):
                    placeholderPreview(icon: "exclamationmark.triangle", message: message)

                case let .image(preview):
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tokens.previewFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(tokens.cardBorder, lineWidth: 1)
                            )

                        Image(nsImage: preview.image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .text(preview):
                    textPreviewView(preview)

                case let .file(preview):
                    filePreviewView(preview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
    }

    @ViewBuilder
    private func placeholderPreview(icon: String, message: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tokens.previewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func textPreviewView(_ preview: QuickTextPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(preview.characterCount) chars · \(preview.lineCount) lines\(preview.truncated ? " · truncated" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            ScrollView {
                Text(preview.text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tokens.previewFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tokens.cardBorder, lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func filePreviewView(_ preview: QuickFilePreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(preview.files.count) files")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.files) { file in
                            Button {
                                model.previewSelectedFilePath = file.path
                            } label: {
                                HStack(spacing: 4) {
                                    Text(file.name)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 4)
                                    if !file.exists {
                                        Text("Missing")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .glassStatusStyle(glassCapability, kind: .warning)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(preview.selectedPath == file.path ? tokens.statusFill(.neutral) : AnyShapeStyle(Color.clear))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                }
                .frame(width: 110)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tokens.previewFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(tokens.cardBorder, lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 6) {
                    fileMetaRow(title: "Name", value: preview.selectedMetadata.name)
                    fileMetaRow(
                        title: "Path",
                        value: preview.selectedMetadata.path,
                        lineLimit: 1,
                        truncationMode: .middle,
                        tooltip: preview.selectedMetadata.path
                    )
                    fileMetaRow(title: "Status", value: preview.selectedMetadata.exists ? "Available" : "Missing")
                    fileMetaRow(title: "Size", value: preview.selectedMetadata.sizeText)
                    fileMetaRow(title: "Modified", value: preview.selectedMetadata.modifiedText)

                    HStack(spacing: 6) {
                        Button("Reveal") {
                            revealFile(path: preview.selectedMetadata.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Copy Path") {
                            copyPath(preview.selectedMetadata.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func fileMetaRow(
        title: String,
        value: String,
        lineLimit: Int = 2,
        truncationMode: Text.TruncationMode = .tail,
        tooltip: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(lineLimit)
                .truncationMode(truncationMode)
                .textSelection(.enabled)
                .help(tooltip ?? value)
        }
    }

    private var activePreviewEntry: QuickPickerEntry? {
        if let hoveredEntryID,
           let hoveredEntry = model.entries.first(where: { $0.id == hoveredEntryID })
        {
            return hoveredEntry
        }

        if let selectedEntryID,
           let selectedEntry = model.entries.first(where: { $0.id == selectedEntryID })
        {
            return selectedEntry
        }

        return nil
    }

    private var previewSelectionTitle: String {
        guard let previewEntry = activePreviewEntry else {
            return "No selection"
        }

        let trimmed = previewEntry.displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return kindFallbackTitle(for: previewEntry.kind)
    }

    private var hoveredEntryID: UUID? {
        model.hoveredEntryID
    }

    private var selectedEntryID: UUID? {
        model.selectedEntryID
    }

    private func updatePreviewContent() {
        guard state.currentTab == .quick else {
            previewContent = .none
            return
        }

        let resolved = previewResolver.resolve(entry: activePreviewEntry, selectedFilePath: model.previewSelectedFilePath)
        previewContent = resolved

        switch resolved {
        case let .file(filePreview):
            if model.previewSelectedFilePath != filePreview.selectedPath {
                model.previewSelectedFilePath = filePreview.selectedPath
            }
        default:
            if model.previewSelectedFilePath != nil {
                model.previewSelectedFilePath = nil
            }
        }
    }

    private func requestFocusIfNeeded() {
        guard state.currentTab == .quick else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func revealFile(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    private func sourceText(for entry: QuickPickerEntry) -> String {
        entry.sourceAppName ?? "Unknown app"
    }

    @ViewBuilder
    private func sourceView(for entry: QuickPickerEntry) -> some View {
        HStack(spacing: 6) {
            sourceIcon(for: entry)

            Text(sourceText(for: entry))
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sourceIcon(for entry: QuickPickerEntry) -> some View {
        if let icon = sourceAppIconProvider(entry.sourceBundleId) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
        }
    }

    private func timeCaption(for entry: QuickPickerEntry) -> String {
        "\(entry.sourceTimeText) · \(relativeTimeText(since: entry.capturedAt))"
    }

    private func rowStatus(for entry: QuickPickerEntry) -> QuickEntryStatus {
        if let cached = rowStatuses[entry.id] {
            return cached
        }
        return entryStatusResolver.resolve(for: entry)
    }

    private func refreshRowStatuses() {
        var updated: [UUID: QuickEntryStatus] = [:]
        for entry in model.entries {
            updated[entry.id] = entryStatusResolver.resolve(for: entry)
        }
        rowStatuses = updated
    }

    private func kindFallbackTitle(for kind: ClipboardItemKind) -> String {
        switch kind {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        }
    }

    private func relativeTimeText(since capturedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(capturedAt)))

        if elapsed < 60 {
            return "Just now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = hours / 24
        return "\(days)d ago"
    }
}

private struct SettingsTabView: View {
    @ObservedObject var coordinator: AppCoordinator
    let onOpenQuick: () -> Void
    let glassCapability: GlassCapability

    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }
    private var shortcutPresetBinding: Binding<QuickPickerShortcutPreset> {
        Binding(
            get: { coordinator.quickPickerShortcutPreset },
            set: { coordinator.updateQuickPickerShortcut($0) }
        )
    }
    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { coordinator.settings.maxItems },
            set: { coordinator.updateMaxItems($0) }
        )
    }
    private var setupReadyCount: Int {
        coordinator.setupChecks.filter { $0.status == .ready }.count
    }
    private var setupTotalCount: Int {
        coordinator.setupChecks.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                quickActionsSection
                preferencesSection
                setupChecksSection

                if coordinator.showAccessibilityHintBanner || coordinator.permissionReminder.shouldShowBanner {
                    alertsSection
                }
            }
            .padding(10)
        }
        .glassCardStyle(glassCapability)
    }

    private var quickActionsSection: some View {
        settingsSectionCard(title: "Quick Actions", subtitle: "Frequent commands") {
            Button("Open Clipboard (\(coordinator.quickPickerShortcutPreset.displayName))") {
                onOpenQuick()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var preferencesSection: some View {
        settingsSectionCard(title: "Preferences", subtitle: "Keyboard and storage") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Open Shortcut", selection: shortcutPresetBinding) {
                        ForEach(QuickPickerShortcutPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Stored Items")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper(value: maxItemsBinding, in: SettingsStore.maxItemsRange) {
                        Text("\(coordinator.settings.maxItems) items")
                    }

                    Text("Allowed range: \(SettingsStore.maxItemsRange.lowerBound)-\(SettingsStore.maxItemsRange.upperBound)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var setupChecksSection: some View {
        settingsSectionCard(
            title: "Setup Checks",
            subtitle: setupTotalCount > 0 ? "\(setupReadyCount)/\(setupTotalCount) ready" : "No checks"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SwiftUI.ForEach(coordinator.setupChecks.indices, id: \.self) { index in
                    setupCheckRow(coordinator.setupChecks[index])
                }
            }
        }
    }

    private var alertsSection: some View {
        settingsSectionCard(title: "Alerts", subtitle: "Needs attention") {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.showAccessibilityHintBanner {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto paste is blocked by Accessibility permission.")
                            .font(.caption)
                        Text("Open Setup Checks > Accessibility to resolve.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassStatusStyle(glassCapability, kind: .warning)
                }

                if coordinator.permissionReminder.shouldShowBanner {
                    HStack(spacing: 8) {
                        Text("Permission warning: repeated auto-paste failure")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassStatusStyle(glassCapability, kind: .warning)
                }
            }
        }
    }

    @ViewBuilder
    private func setupCheckRow(_ check: SetupCheckItem) -> some View {
        let loginItemTooltip = "Starts the app automatically when you log in to your Mac."

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if check.title == "Login Item" {
                    Text(check.title)
                        .help(loginItemTooltip)
                } else {
                    Text(check.title)
                }

                Text(check.status == .ready ? "Configured" : "Action needed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(check.status.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(tokens.statusForeground(statusKind(for: check.status)))
                .glassStatusStyle(glassCapability, kind: statusKind(for: check.status))

            setupActionButton(for: check)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tokens.previewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func setupActionButton(for check: SetupCheckItem) -> some View {
        if check.title == "Accessibility" {
            if check.status == .actionRequired {
                Button("Fix Now") {
                    coordinator.performSetupAction(.openAccessibilityGuide)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Open Guide") {
                    coordinator.performSetupAction(.openAccessibilityGuide)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if let action = check.action, check.status == .actionRequired {
            Button("Fix") {
                coordinator.performSetupAction(action)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func statusKind(for status: SetupCheckStatus) -> GlassStatusKind {
        status == .ready ? .success : .warning
    }

    @ViewBuilder
    private func settingsSectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tokens.previewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct AccessibilitySetupGuideView: View {
    @ObservedObject var coordinator: AppCoordinator
    let glassCapability: GlassCapability
    @State private var showAdvancedActions = false

    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }
    private var statusKind: GlassStatusKind {
        coordinator.accessibilityDiagnostics.isTrusted ? .success : .warning
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection

                    if let guidance = coordinator.accessibilityDiagnostics.guidanceReason {
                        warningCard(guidance)
                    }

                    stepCard(
                        index: "1",
                        title: "Open Accessibility Settings",
                        detail: "System Settings > Privacy & Security > Accessibility"
                    ) {
                        Button("Open Settings") {
                            coordinator.performSetupAction(.openAccessibilitySettings)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    stepCard(
                        index: "2",
                        title: "Enable \(coordinator.appDisplayName)",
                        detail: "If app is missing, click + and select the running app, then turn the toggle ON."
                    ) {
                        appIdentityCard
                    }

                    stepCard(
                        index: "3",
                        title: "Return and verify",
                        detail: "After updating the toggle, come back here and run Re-check."
                    ) {
                        Button("Re-check") {
                            coordinator.refreshAccessibilityDiagnostics()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    advancedSection
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    coordinator.closeAccessibilityGuide()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 740, minHeight: 420, alignment: .topLeading)
        .glassContainerStyle(glassCapability)
        .onAppear {
            coordinator.refreshAccessibilityDiagnostics()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accessibility Setup")
                .font(.title3.bold())

            HStack(spacing: 8) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(coordinator.accessibilityDiagnostics.isTrusted ? "Ready" : "Action Required")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(tokens.statusForeground(statusKind))
                    .glassStatusStyle(glassCapability, kind: statusKind)
            }

            Text("Follow steps in order, then click Re-check.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func warningCard(_ guidance: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Guidance")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(guidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassStatusStyle(glassCapability, kind: .warning)
    }

    @ViewBuilder
    private func stepCard<Content: View>(
        index: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassStatusStyle(glassCapability, kind: .neutral)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                content()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tokens.previewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )
        )
    }

    private var appIdentityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            identityRow(title: "App Path", value: coordinator.accessibilityDiagnostics.appPath)
            identityRow(title: "Bundle ID", value: coordinator.accessibilityDiagnostics.bundleId)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tokens.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func identityRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedActions) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Reveal App") {
                        coordinator.revealRunningAppInFinder()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy App Path") {
                        coordinator.copyRunningAppPath()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button("Request Prompt") {
                        coordinator.requestAccessibilityPrompt()
                    }
                    .buttonStyle(.bordered)

                    Button("Request Again") {
                        coordinator.requestAccessibilityPrompt(force: true)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tokens.previewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tokens.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct QuickPickerImageThumbnail: View {
    let payloadPath: String?
    let glassCapability: GlassCapability
    let size: CGFloat
    @State private var image: NSImage?

    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }
    private var cornerRadius: CGFloat { size <= 20 ? 4 : 5 }
    private var iconSize: CGFloat { max(10, size * 0.42) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(tokens.previewFill)
                    Image(systemName: "photo")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(tokens.cardBorder, lineWidth: 0.5)
        )
        .onAppear { loadImageIfNeeded() }
    }

    private func loadImageIfNeeded() {
        guard image == nil, let payloadPath, !payloadPath.isEmpty else { return }
        image = NSImage(contentsOfFile: payloadPath)
    }
}

private struct QuickPickerFileThumbnail: View {
    let isMultipleFiles: Bool
    let glassCapability: GlassCapability
    let size: CGFloat

    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }
    private var cornerRadius: CGFloat { size <= 20 ? 4 : 5 }
    private var iconSize: CGFloat { max(10, size * 0.42) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tokens.statusFill(.neutral))
            Image(systemName: isMultipleFiles ? "shippingbox.fill" : "doc.fill")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tokens.statusForeground(.neutral))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(tokens.cardBorder, lineWidth: 0.5)
        )
    }
}

private struct QuickPickerTextThumbnail: View {
    let glassCapability: GlassCapability
    let size: CGFloat

    private var tokens: GlassTokens { GlassTokens(capability: glassCapability) }
    private var cornerRadius: CGFloat { size <= 20 ? 4 : 5 }
    private var iconSize: CGFloat { max(10, size * 0.42) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tokens.previewFill)
            Image(systemName: "text.alignleft")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(tokens.cardBorder, lineWidth: 0.5)
        )
    }
}
