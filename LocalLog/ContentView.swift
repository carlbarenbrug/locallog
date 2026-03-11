import SwiftUI
import AppKit
import AVFoundation

private let shortcutBadgeSpacing: CGFloat = 2

enum LogEntryKind: String {
    case text
    case video
}

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    var filename: String
    let timestamp: Date
    var previewText: String
    var cachedContent: String
    var kind: LogEntryKind
    var transcriptFilename: String?
    var recordingDurationSeconds: Double?
}

private struct ShortcutBadge: View {
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    private var badgeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0x30 / 255.0, green: 0x30 / 255.0, blue: 0x30 / 255.0)
            : Color.white
    }

    private var badgeBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.16)
    }

    private var badgeText: Color {
        colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.75)
    }

    var body: some View {
        Text(value)
            .font(.system(size: 10, weight: .regular, design: .default))
            .foregroundColor(badgeText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(badgeBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct HoverOpacityButton: View {
    let title: String
    let shortcuts: [String]
    let showShortcuts: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showShortcuts {
                    HStack(spacing: shortcutBadgeSpacing) {
                        ForEach(shortcuts, id: \.self) { shortcut in
                            ShortcutBadge(value: shortcut)
                        }
                    }
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.opacity)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 0.7 : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct ContentView: View {
    private static let storageDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Local Log", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    private let fileManager = FileManager.default
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    private let sidebarTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
    private let appFontCandidates = [
        "GeistMono-Regular",
        "Geist Mono"
    ]

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("fontSize") private var storedFontSize: Double = 18

    @State private var entries: [LogEntry] = []
    @State private var selectedEntryId: UUID?
    @State private var text: String = ""
    @State private var showingSidebar = true
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false

    @State private var editingTitleEntryId: UUID?
    @State private var titleDraft = ""

    @State private var pendingSaveWorkItem: DispatchWorkItem?
    @State private var isFullscreen = false
    @State private var hoveredEntryId: UUID?
    @State private var footerVisible = true
    @State private var suppressFooterAutoHide = false
    @State private var windowWidth: CGFloat = 1100
    @State private var windowHeight: CGFloat = 760
    @State private var sidebarWidth: CGFloat = 320
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var sidebarHovering = false
    @State private var openZoneHovering = false
    @State private var swipeMonitor: Any?
    @State private var swipeAccumX: CGFloat = 0
    @State private var isVideoRecorderPresented = false
    @State private var showVideoTranscriptEditor = true
    @State private var isHoveringTranscriptToggle = false
    @State private var isHoveringTranscriptClose = false

    @FocusState private var searchFieldFocused: Bool
    @FocusState private var focusedTitleEntryId: UUID?
    @FocusState private var editorFocused: Bool

    private var editorBackgroundColor: Color {
        colorScheme == .dark
            ? Color(NSColor.windowBackgroundColor)
            : Color(red: 0xF9 / 255.0, green: 0xF9 / 255.0, blue: 0xF9 / 255.0)
    }

    private var editorTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0)
            : .white
    }

    private var filteredEntries: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            let title = titleForEntry(entry).lowercased()
            let preview = entry.previewText.lowercased()
            let timestampText = sidebarTimestampFormatter.string(from: entry.timestamp).lowercased()
            let content = entry.cachedContent.lowercased()
            return title.contains(query) || preview.contains(query) || timestampText.contains(query) || content.contains(query)
        }
    }

    private var fontSize: CGFloat {
        CGFloat(storedFontSize)
    }

    private var editorFontSize: CGFloat {
        fontSize * 0.9
    }

    private var sidebarBorderColor: Color {
        colorScheme == .dark
            ? Color(red: 0x34 / 255.0, green: 0x34 / 255.0, blue: 0x34 / 255.0)
            : Color.black.opacity(0.12)
    }

    private var appTopBorderColor: Color {
        sidebarBorderColor
    }

    private var selectedRowBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0x30 / 255.0, green: 0x30 / 255.0, blue: 0x30 / 255.0)
            : Color(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF2 / 255.0)
    }

    private var tagBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.16)
    }

    private var searchHighlightBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.88)
    }

    private var searchHighlightTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var hairlineWidth: CGFloat {
        1.0 / (NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    private var wordCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var selectedEntry: LogEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first(where: { $0.id == selectedEntryId })
    }

    private var isSelectedEntryVideo: Bool {
        selectedEntry?.kind == .video
    }

    private func recordingDurationText(for entry: LogEntry) -> String? {
        guard entry.kind == .video, let duration = entry.recordingDurationSeconds else { return nil }
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private let editorBaseTopPadding: CGFloat = 26
    private let editorTopTargetInset: CGFloat = 62

    private var showSearchShortcutBadges: Bool {
        searchText.isEmpty && !searchFieldFocused
    }

    private var shouldHideFooterShortcuts: Bool {
        footerAvailableWidth < 980
    }

    private var shouldHideFontSizeButtons: Bool {
        footerAvailableWidth < 760
    }

    private var footerAvailableWidth: CGFloat {
        let occupiedSidebarWidth: CGFloat = showingSidebar ? (sidebarWidth + 1) : 0
        return max(0, windowWidth - occupiedSidebarWidth)
    }

    private let minSidebarWidth: CGFloat = 260
    private let maxSidebarWidth: CGFloat = 520
    private let swipeOpenZoneBottomInset: CGFloat = 58

    private func editorTopPadding(for safeAreaTop: CGFloat) -> CGFloat {
        max(editorBaseTopPadding, editorTopTargetInset - safeAreaTop)
    }

    private var appFontName: String? {
        appFontCandidates.first(where: { NSFont(name: $0, size: 12) != nil })
    }

    private func appFont(_ size: CGFloat) -> Font {
        if let fontName = appFontName {
            return .custom(fontName, size: size)
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    var body: some View {
        HStack(spacing: 0) {
            mainEditor

            if showingSidebar {
                sidebar
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .leading) {
                        sidebarResizeOverlay
                    }
                    .onHover { hovering in
                        sidebarHovering = hovering
                    }
                    .transition(.move(edge: .trailing))
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                if value.translation.width < -70 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showingSidebar = false
                                    }
                                }
                            }
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appTopBorderColor)
                .frame(height: hairlineWidth)
        }
        .overlay(alignment: .topTrailing) {
            if !showingSidebar && !isSelectedEntryVideo {
                Color.clear
                    .frame(
                        width: max(24, windowWidth * 0.2),
                        height: max(0, windowHeight - swipeOpenZoneBottomInset),
                        alignment: .top
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        openZoneHovering = hovering
                    }
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                if value.translation.width > 70 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showingSidebar = true
                                    }
                                }
                            }
                    )
            }
        }
        .onAppear {
            loadExistingEntries()
            isFullscreen = NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true
            installSwipeMonitorIfNeeded()
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
        .onDisappear {
            removeSwipeMonitor()
        }
        .onChange(of: text) { oldValue, newValue in
            updateSelectedEntryPreviewInMemory()
            syncAutoGeneratedTitleForSelectedEntry(from: oldValue, to: newValue)
            scheduleDebouncedSave()
            if !suppressFooterAutoHide && editorFocused && !isVideoRecorderPresented {
                withAnimation(.easeOut(duration: 0.22)) {
                    footerVisible = false
                }
            }
        }
        .onChange(of: focusedTitleEntryId) { _, newValue in
            if editingTitleEntryId != nil && newValue == nil {
                commitTitleEdit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.newEntry)) { _ in
            createNewEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.startVideoEntry)) { _ in
            startVideoEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.toggleHistory)) { _ in
            showingSidebar.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.toggleFullscreen)) { _ in
            toggleFullscreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.focusSearch)) { _ in
            showingSidebar = true
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.deleteEntry)) { _ in
            if selectedEntryId != nil {
                showingDeleteConfirmation = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.increaseTextSize)) { _ in
            increaseTextSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.decreaseTextSize)) { _ in
            decreaseTextSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: LogCommand.resetTextSize)) { _ in
            resetTextSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedEntry()
            }
            Button("Cancel", role: .cancel) {}
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        windowWidth = proxy.size.width
                        windowHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        windowWidth = newValue
                    }
                    .onChange(of: proxy.size.height) { _, newValue in
                        windowHeight = newValue
                    }
            }
        )
    }

    private var sidebarResizeOverlay: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(sidebarBorderColor)
                 .frame(width: hairlineWidth)
                .offset(x: -hairlineWidth)
                .ignoresSafeArea()

            Color.clear
                .frame(width: 10)
                .offset(x: -4.5)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if sidebarDragStartWidth == nil {
                                sidebarDragStartWidth = sidebarWidth
                            }
                            let baseWidth = sidebarDragStartWidth ?? sidebarWidth
                            let proposed = baseWidth - value.translation.width
                            sidebarWidth = min(max(proposed, minSidebarWidth), maxSidebarWidth)
                        }
                        .onEnded { _ in
                            sidebarDragStartWidth = nil
                        }
                )
        }
    }

    private func installSwipeMonitorIfNeeded() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleTrackpadSwipe(event)
            return event
        }
    }

    private func removeSwipeMonitor() {
        if let monitor = swipeMonitor {
            NSEvent.removeMonitor(monitor)
            swipeMonitor = nil
        }
    }

    private func handleTrackpadSwipe(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY

        guard abs(horizontal) > abs(vertical) else {
            if event.phase == .ended || event.momentumPhase == .ended {
                swipeAccumX = 0
            }
            return
        }

        if event.phase == .began {
            swipeAccumX = 0
        }
        swipeAccumX += horizontal

        let threshold: CGFloat = 55

        if showingSidebar && sidebarHovering {
            if swipeAccumX > threshold {
                withAnimation(.easeOut(duration: 0.2)) {
                    showingSidebar = false
                }
                swipeAccumX = 0
            }
        } else if !showingSidebar && openZoneHovering {
            if swipeAccumX < -threshold {
                withAnimation(.easeOut(duration: 0.2)) {
                    showingSidebar = true
                }
                swipeAccumX = 0
            }
        }

        if event.phase == .ended || event.momentumPhase == .ended {
            swipeAccumX = 0
        }
    }

    private var mainEditor: some View {
        Group {
            if isVideoRecorderPresented {
                VideoRecordingView(
                    isPresented: $isVideoRecorderPresented,
                    onRecordingComplete: { videoURL, transcript in
                        createVideoEntry(from: videoURL, transcript: transcript)
                        isVideoRecorderPresented = false
                    },
                    onCloseWithoutRecording: {
                        createNewEntry()
                        isVideoRecorderPresented = false
                    }
                )
            } else {
                VStack(spacing: 0) {
                    if isSelectedEntryVideo {
                        videoEntrySurface
                    } else {
                        textEntrySurface
                    }

                    bottomToolbar
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    footerVisible = true
                                }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textEntrySurface: some View {
        GeometryReader { proxy in
            let topPadding = editorTopPadding(for: proxy.safeAreaInsets.top)
            ZStack(alignment: .topLeading) {
                editorBackgroundColor
                    .ignoresSafeArea()

                TextEditor(text: $text)
                    .font(appFont(editorFontSize))
                    .foregroundColor(editorTextColor)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .padding(.horizontal, 24)
                    .padding(.top, topPadding)
                    .padding(.bottom, 16)

                if text.isEmpty {
                    Text("log something...")
                        .font(appFont(editorFontSize))
                        .foregroundColor(editorTextColor.opacity(0.55))
                        .padding(.leading, 30)
                        .padding(.top, topPadding)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var videoEntrySurface: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if let videoURL = videoURLForSelectedEntry {
                    VideoPlayerView(videoURL: videoURL, isPlaybackSuspended: false, shouldAutoPlay: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    Color.black
                        .overlay {
                            Text("video unavailable")
                                .font(appFont(13))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.62), Color.black.opacity(0.24), Color.clear]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 160)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if !showVideoTranscriptEditor {
                    Button("show notes") {
                        showVideoTranscriptEditor = true
                    }
                    .buttonStyle(.plain)
                    .font(appFont(13))
                    .foregroundColor(Color.white.opacity(0.92))
                    .opacity(isHoveringTranscriptToggle ? 0.7 : 1.0)
                    .onHover { hovering in
                        isHoveringTranscriptToggle = hovering
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }

            if showVideoTranscriptEditor {
                Rectangle()
                    .fill(sidebarBorderColor)
                    .frame(height: hairlineWidth)

                ZStack(alignment: .topLeading) {
                    editorBackgroundColor

                    TextEditor(text: $text)
                        .font(appFont(editorFontSize))
                        .foregroundColor(editorTextColor)
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    if text.isEmpty {
                        Text("add video notes...")
                            .font(appFont(editorFontSize))
                            .foregroundColor(editorTextColor.opacity(0.55))
                            .padding(.leading, 30)
                            .padding(.top, 24)
                            .allowsHitTesting(false)
                    }

                    HStack {
                        Spacer()
                        Button("hide notes") {
                            showVideoTranscriptEditor = false
                        }
                        .buttonStyle(.plain)
                        .font(appFont(13))
                        .foregroundColor(editorTextColor.opacity(0.78))
                        .opacity(isHoveringTranscriptClose ? 0.7 : 1.0)
                        .onHover { hovering in
                            isHoveringTranscriptClose = hovering
                        }
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                    }
                }
                .frame(height: min(max(160, windowHeight * 0.24), 260))
            }
        }
        .background(editorBackgroundColor)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 14) {
            if !shouldHideFontSizeButtons {
                HStack(spacing: 8) {
                    HoverOpacityButton(title: "A-", shortcuts: ["⌘", "-"], showShortcuts: !shouldHideFooterShortcuts) { decreaseTextSize() }
                    HoverOpacityButton(title: "A", shortcuts: ["⌘", "0"], showShortcuts: !shouldHideFooterShortcuts) { resetTextSize() }
                    HoverOpacityButton(title: "A+", shortcuts: ["⌘", "+"], showShortcuts: !shouldHideFooterShortcuts) { increaseTextSize() }
                }
            }

            Spacer()

            Text("\(wordCount) words")
                .font(appFont(13))
                .foregroundColor(editorTextColor.opacity(0.65))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            footerDivider

            HoverOpacityButton(title: "fullscreen", shortcuts: ["⌃", "⌘", "F"], showShortcuts: !shouldHideFooterShortcuts) {
                toggleFullscreen()
            }
            .animation(.easeInOut(duration: 0.24), value: isFullscreen)

            footerDivider

            HoverOpacityButton(title: "new entry", shortcuts: ["⌘", "N"], showShortcuts: !shouldHideFooterShortcuts) {
                createNewEntry()
            }

            footerDivider

            HoverOpacityButton(title: "video", shortcuts: ["⌘", "R"], showShortcuts: !shouldHideFooterShortcuts) {
                startVideoEntry()
            }

            footerDivider

            HoverOpacityButton(title: "archive", shortcuts: ["⌘", "H"], showShortcuts: !shouldHideFooterShortcuts) {
                showingSidebar.toggle()
            }
        }
        .font(appFont(13))
        .foregroundColor(editorTextColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(footerVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.22), value: footerVisible)
        .frame(maxWidth: .infinity)
        .background(editorBackgroundColor)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(sidebarBorderColor)
                .frame(height: hairlineWidth)
                .opacity(footerVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: footerVisible)
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(sidebarBorderColor)
            .frame(width: 1, height: 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .leading) {
                    HStack(spacing: shortcutBadgeSpacing) {
                        ShortcutBadge(value: "⌘")
                        ShortcutBadge(value: "F")
                    }
                    .padding(.leading, 10)
                    .opacity(showSearchShortcutBadges ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: showSearchShortcutBadges)

                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("search")
                            .font(appFont(13))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    )
                        .textFieldStyle(.plain)
                        .font(appFont(13))
                        .focused($searchFieldFocused)
                        .padding(.vertical, 10)
                        .padding(.trailing, 10)
                        .padding(.leading, showSearchShortcutBadges ? 58 : 10)
                        .animation(.easeOut(duration: 0.18), value: showSearchShortcutBadges)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(sidebarBorderColor, lineWidth: hairlineWidth)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 46)
            .padding(.bottom, 12)

            Rectangle()
                .fill(sidebarBorderColor)
                .frame(height: hairlineWidth)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        sidebarRow(for: entry)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, -1)
            }
            .contentMargins(.zero, for: .scrollContent)
        }
        .background(sidebarBackgroundColor)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func sidebarRow(for entry: LogEntry) -> some View {
        let isSelected = selectedEntryId == entry.id
        let isHovered = hoveredEntryId == entry.id
        let titleText = titleForEntry(entry)
        let timestampText = sidebarTimestampFormatter.string(from: entry.timestamp)
        let previewValue = entry.previewText.isEmpty
            ? (entry.kind == .video ? (recordingDurationText(for: entry) ?? "0:00") : "no content")
            : entry.previewText
        let rowBackgroundColor: Color = isSelected
            ? selectedRowBackgroundColor
            : (isHovered
                ? (colorScheme == .dark
                    ? Color(red: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0)
                    : Color(red: 0xF9 / 255.0, green: 0xF9 / 255.0, blue: 0xF9 / 255.0))
                : Color.clear)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if editingTitleEntryId == entry.id {
                        TextField("Title", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(appFont(13))
                            .focused($focusedTitleEntryId, equals: entry.id)
                            .onSubmit {
                                commitTitleEdit()
                            }
                    } else {
                        Text(highlightedAttributedString(for: titleText))
                            .font(appFont(13))
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                beginTitleEdit(for: entry)
                            }
                    }

                    Text(entry.kind.rawValue)
                        .font(appFont(10))
                        .textCase(.lowercase)
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.24) : Color.white.opacity(0.9))
                        )
                            .overlay(
                                Capsule()
                                    .stroke(tagBorderColor, lineWidth: 1)
                            )
                }

                Spacer(minLength: 8)

                Text(highlightedAttributedString(for: timestampText))
                    .font(appFont(11))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                    .lineLimit(1)
            }

            Text(highlightedAttributedString(for: previewValue))
                .font(appFont(11))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor)
        .contentShape(Rectangle())
        .onTapGesture {
            selectEntry(entry)
        }
        .onHover { hovering in
            hoveredEntryId = hovering ? entry.id : (hoveredEntryId == entry.id ? nil : hoveredEntryId)
        }
        .contextMenu {
            Button("Rename") {
                beginTitleEdit(for: entry)
            }
            Button("Show in Finder") {
                showEntryInFinder(entry)
            }
            Button("Delete", role: .destructive) {
                selectedEntryId = entry.id
                showingDeleteConfirmation = true
            }
        }
    }

    private func beginTitleEdit(for entry: LogEntry) {
        editingTitleEntryId = entry.id
        titleDraft = titleForEntry(entry)
        focusedTitleEntryId = entry.id
    }

    private func commitTitleEdit() {
        guard let entryId = editingTitleEntryId else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            renameEntryFiles(at: index, to: trimmed.isEmpty ? "untitled" : trimmed)
        }

        editingTitleEntryId = nil
        focusedTitleEntryId = nil
        titleDraft = ""
    }

    private func titleForEntry(_ entry: LogEntry) -> String {
        storedBaseName(for: entry).replacingOccurrences(of: "-", with: " ")
    }

    private func toggleFullscreen() {
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFullscreen = NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true
        }
    }

    private func increaseTextSize() {
        storedFontSize = min(storedFontSize + 1, 36)
    }

    private func decreaseTextSize() {
        storedFontSize = max(storedFontSize - 1, 12)
    }

    private func resetTextSize() {
        storedFontSize = 18
    }

    private var videoURLForSelectedEntry: URL? {
        guard let entry = selectedEntry, entry.kind == .video else { return nil }
        let videoURL = ContentView.storageDirectory.appendingPathComponent(entry.filename)
        return fileManager.fileExists(atPath: videoURL.path) ? videoURL : nil
    }

    private func startVideoEntry() {
        commitTitleEdit()
        flushPendingSave()
        showingSidebar = false
        isVideoRecorderPresented = true
        editorFocused = false
        footerVisible = true
    }

    private func scheduleDebouncedSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            saveSelectedEntryNow()
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        saveSelectedEntryNow()
    }

    private func createNewEntry() {
        flushPendingSave()

        let entry = LogEntry.createNew(with: timestampFormatter)
        entries.insert(entry, at: 0)
        selectedEntryId = entry.id
        suppressFooterAutoHide = true
        text = ""
        suppressFooterAutoHide = false
        editorFocused = true
        saveSelectedEntryNow()
    }

    private func createVideoEntry(from temporaryVideoURL: URL, transcript: String) {
        flushPendingSave()

        let durationSeconds = recordingDurationSeconds(for: temporaryVideoURL)
        let entry = LogEntry.createVideoEntry(with: timestampFormatter, transcript: transcript, durationSeconds: durationSeconds)
        let destinationVideoURL = ContentView.storageDirectory.appendingPathComponent(entry.filename)

        do {
            if fileManager.fileExists(atPath: destinationVideoURL.path) {
                try fileManager.removeItem(at: destinationVideoURL)
            }
            try fileManager.moveItem(at: temporaryVideoURL, to: destinationVideoURL)

            if let transcriptFilename = entry.transcriptFilename {
                let transcriptURL = ContentView.storageDirectory.appendingPathComponent(transcriptFilename)
                try entry.cachedContent.write(to: transcriptURL, atomically: true, encoding: .utf8)
            }

            entries.insert(entry, at: 0)
            selectedEntryId = entry.id
            suppressFooterAutoHide = true
            text = entry.cachedContent
            suppressFooterAutoHide = false
            editorFocused = true
        } catch {
            print("Failed to persist video entry: \(error)")
            try? fileManager.removeItem(at: temporaryVideoURL)
        }
    }

    private func selectEntry(_ entry: LogEntry) {
        guard selectedEntryId != entry.id else { return }
        commitTitleEdit()
        flushPendingSave()

        withAnimation(.easeOut(duration: 0.22)) {
            footerVisible = true
        }
        showVideoTranscriptEditor = true
        selectedEntryId = entry.id
        suppressFooterAutoHide = true
        text = loadText(for: entry)
        suppressFooterAutoHide = false
        editorFocused = entry.kind == .text
    }

    private func deleteSelectedEntry() {
        guard let selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == selectedEntryId }) else {
            return
        }

        let entry = entries[index]
        let fileURL = ContentView.storageDirectory.appendingPathComponent(entry.filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
        if let transcriptFilename = entry.transcriptFilename {
            let transcriptURL = ContentView.storageDirectory.appendingPathComponent(transcriptFilename)
            if fileManager.fileExists(atPath: transcriptURL.path) {
                try? fileManager.removeItem(at: transcriptURL)
            }
        }

        entries.remove(at: index)

        if let replacement = entries.first {
            self.selectedEntryId = replacement.id
            text = loadText(for: replacement)
        } else {
            createNewEntry()
        }
    }

    private func saveSelectedEntryNow() {
        guard let selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == selectedEntryId }) else {
            return
        }

        if entries[index].kind == .video, entries[index].transcriptFilename == nil {
            entries[index].transcriptFilename = defaultTranscriptFilename(forVideoFilename: entries[index].filename)
        }

        let entry = entries[index]
        let targetFilename = entry.kind == .text ? entry.filename : (entry.transcriptFilename ?? "")
        guard !targetFilename.isEmpty else { return }

        let fileURL = ContentView.storageDirectory.appendingPathComponent(targetFilename)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            entries[index].cachedContent = text
            entries[index].previewText = previewText(from: text)
        } catch {
            print("Failed to save entry: \(error)")
        }
    }

    private func updateSelectedEntryPreviewInMemory() {
        guard let selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == selectedEntryId }) else {
            return
        }

        entries[index].cachedContent = text
        entries[index].previewText = previewText(from: text)
    }

    private func previewText(from content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }
        let prefix = String(normalized.prefix(90))
        return normalized.count > 90 ? prefix + "..." : prefix
    }

    private var searchTokens: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    private func highlightedAttributedString(for value: String) -> AttributedString {
        var attributed = AttributedString(value)
        guard !value.isEmpty else { return attributed }

        let base = value.lowercased()
        for token in searchTokens {
            var searchStart = base.startIndex
            while searchStart < base.endIndex,
                  let range = base.range(of: token, options: [], range: searchStart..<base.endIndex) {
                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].backgroundColor = searchHighlightBackgroundColor
                    attributed[attributedRange].foregroundColor = searchHighlightTextColor
                }
                searchStart = range.upperBound
            }
        }

        return attributed
    }

    private func hasCompletedFirstWord(in content: String) -> Bool {
        content.range(of: #"\S+\s+"#, options: .regularExpression) != nil
    }

    private func autoGeneratedTitle(for content: String) -> String {
        guard hasCompletedFirstWord(in: content) else { return "untitled" }
        let generated = previewText(from: content)
        return generated.isEmpty ? "untitled" : generated
    }

    private func syncAutoGeneratedTitleForSelectedEntry(from oldContent: String, to newContent: String) {
        guard let selectedEntryId,
              let index = entries.firstIndex(where: { $0.id == selectedEntryId }),
              entries[index].kind == .text,
              editingTitleEntryId == nil else {
            return
        }

        let currentBaseName = storedBaseName(for: entries[index])
        let previousAutoBaseName = sanitizeStoredBaseName(autoGeneratedTitle(for: oldContent))

        // Only keep auto-renaming while the filename still reflects the generated title.
        guard currentBaseName == previousAutoBaseName else { return }

        let nextAutoTitle = autoGeneratedTitle(for: newContent)
        if sanitizeStoredBaseName(nextAutoTitle) != currentBaseName {
            renameEntryFiles(at: index, to: nextAutoTitle)
        }
    }

    private func loadText(for entry: LogEntry) -> String {
        let sourceFilename: String
        if entry.kind == .text {
            sourceFilename = entry.filename
        } else {
            sourceFilename = entry.transcriptFilename ?? defaultTranscriptFilename(forVideoFilename: entry.filename)
        }
        guard !sourceFilename.isEmpty else { return "" }
        let fileURL = ContentView.storageDirectory.appendingPathComponent(sourceFilename)
        guard let value = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return value
    }

    private func defaultTranscriptFilename(forVideoFilename videoFilename: String) -> String {
        videoFilename.replacingOccurrences(of: ".mov", with: "-notes.md")
    }

    private func recordingDurationSeconds(for videoURL: URL) -> Double? {
        let asset = AVURLAsset(url: videoURL)
        let durationSeconds = asset.duration.seconds
        guard durationSeconds.isFinite, durationSeconds >= 0 else { return nil }
        return durationSeconds
    }

    private func showEntryInFinder(_ entry: LogEntry) {
        let url = ContentView.storageDirectory.appendingPathComponent(entry.filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func storedBaseName(for entry: LogEntry) -> String {
        if let modern = parseModernStoredFilename(entry.filename, pathExtension: entry.kind == .video ? "mov" : "md") {
            return modern.baseName
        }
        return "untitled"
    }

    private func sanitizeStoredBaseName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleanedScalars = title.unicodeScalars.map { invalidCharacters.contains($0) ? " " : Character($0) }
        let cleaned = String(cleanedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    private func timestampStamp(for timestamp: Date) -> String {
        timestampFormatter.string(from: timestamp)
    }

    private func textFilename(baseName: String, timestamp: Date) -> String {
        "\(baseName)-\(timestampStamp(for: timestamp)).md"
    }

    private func videoFilename(baseName: String, timestamp: Date) -> String {
        "\(baseName)-\(timestampStamp(for: timestamp)).mov"
    }

    private func notesFilename(baseName: String, timestamp: Date) -> String {
        "\(baseName)-\(timestampStamp(for: timestamp))-notes.md"
    }

    private func transcriptKey(baseName: String, timestamp: Date) -> String {
        "\(baseName)|\(timestampStamp(for: timestamp))"
    }

    private func parseModernStoredFilename(_ filename: String, pathExtension: String) -> (baseName: String, timestamp: Date)? {
        let pattern = "^(.*)-(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\.\(NSRegularExpression.escapedPattern(for: pathExtension))$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let baseRange = Range(match.range(at: 1), in: filename),
              let timestampRange = Range(match.range(at: 2), in: filename) else {
            return nil
        }
        let baseName = String(filename[baseRange])
        let stamp = String(filename[timestampRange])
        guard let timestamp = timestampFormatter.date(from: stamp) else { return nil }
        return (baseName, timestamp)
    }

    private func parseModernNotesFilename(_ filename: String) -> (baseName: String, timestamp: Date)? {
        let pattern = "^(.*)-(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})-notes\\.md$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let baseRange = Range(match.range(at: 1), in: filename),
              let timestampRange = Range(match.range(at: 2), in: filename) else {
            return nil
        }
        let baseName = String(filename[baseRange])
        let stamp = String(filename[timestampRange])
        guard let timestamp = timestampFormatter.date(from: stamp) else { return nil }
        return (baseName, timestamp)
    }

    private func renameEntryFiles(at index: Int, to title: String) {
        let baseName = sanitizeStoredBaseName(title)
        let entry = entries[index]
        let newPrimaryFilename = entry.kind == .text
            ? textFilename(baseName: baseName, timestamp: entry.timestamp)
            : videoFilename(baseName: baseName, timestamp: entry.timestamp)

        if newPrimaryFilename != entry.filename {
            let currentURL = ContentView.storageDirectory.appendingPathComponent(entry.filename)
            let newURL = ContentView.storageDirectory.appendingPathComponent(newPrimaryFilename)
            if fileManager.fileExists(atPath: currentURL.path) {
                try? fileManager.moveItem(at: currentURL, to: newURL)
            }
            entries[index].filename = newPrimaryFilename
        }

        guard entry.kind == .video else { return }
        let currentNotesFilename = entry.transcriptFilename ?? defaultTranscriptFilename(forVideoFilename: entry.filename)
        let newNotesFile = notesFilename(baseName: baseName, timestamp: entry.timestamp)
        if currentNotesFilename != newNotesFile {
            let currentNotesURL = ContentView.storageDirectory.appendingPathComponent(currentNotesFilename)
            let newNotesURL = ContentView.storageDirectory.appendingPathComponent(newNotesFile)
            if fileManager.fileExists(atPath: currentNotesURL.path) {
                try? fileManager.moveItem(at: currentNotesURL, to: newNotesURL)
            }
            entries[index].transcriptFilename = newNotesFile
        }
    }

    private func parseTextFilename(_ filename: String) -> (id: UUID, timestamp: Date, baseName: String)? {
        if let parsed = parseModernStoredFilename(filename, pathExtension: "md") {
            return (UUID(), parsed.timestamp, parsed.baseName)
        }
        guard filename.hasPrefix("["), filename.hasSuffix("].md"), let divider = filename.range(of: "]-[") else {
            return nil
        }

        let idStart = filename.index(after: filename.startIndex)
        let idString = String(filename[idStart..<divider.lowerBound])
        guard let uuid = UUID(uuidString: idString) else { return nil }

        let timestampStart = divider.upperBound
        let timestampEnd = filename.index(filename.endIndex, offsetBy: -4)
        let timestampString = String(filename[timestampStart..<timestampEnd])
        guard let timestamp = timestampFormatter.date(from: timestampString) else { return nil }

        return (uuid, timestamp, "untitled")
    }

    private func parseVideoFilename(_ filename: String) -> (id: UUID, timestamp: Date, baseName: String)? {
        if let parsed = parseModernStoredFilename(filename, pathExtension: "mov") {
            return (UUID(), parsed.timestamp, parsed.baseName)
        }
        guard filename.hasPrefix("["), filename.hasSuffix("].mov"), let divider = filename.range(of: "]-[") else {
            return nil
        }

        let idStart = filename.index(after: filename.startIndex)
        let idString = String(filename[idStart..<divider.lowerBound])
        guard let uuid = UUID(uuidString: idString) else { return nil }

        let timestampStart = divider.upperBound
        let timestampEnd = filename.index(filename.endIndex, offsetBy: -5)
        let timestampString = String(filename[timestampStart..<timestampEnd])
        guard let timestamp = timestampFormatter.date(from: timestampString) else { return nil }

        return (uuid, timestamp, "untitled")
    }

    private func parseVideoTranscriptFilename(_ filename: String) -> (id: UUID, timestamp: Date, baseName: String)? {
        if let parsed = parseModernNotesFilename(filename) {
            return (UUID(), parsed.timestamp, parsed.baseName)
        }
        guard filename.hasPrefix("["), filename.hasSuffix("]-transcript.md"), let divider = filename.range(of: "]-[") else {
            return nil
        }

        let idStart = filename.index(after: filename.startIndex)
        let idString = String(filename[idStart..<divider.lowerBound])
        guard let uuid = UUID(uuidString: idString) else { return nil }

        let timestampStart = divider.upperBound
        let timestampEnd = filename.index(filename.endIndex, offsetBy: -14)
        let timestampString = String(filename[timestampStart..<timestampEnd])
        guard let timestamp = timestampFormatter.date(from: timestampString) else { return nil }

        return (uuid, timestamp, "untitled")
    }

    private func loadExistingEntries() {
        do {
            let files = try fileManager.contentsOfDirectory(at: ContentView.storageDirectory, includingPropertiesForKeys: nil)
            let transcriptFiles = files.filter {
                $0.lastPathComponent.hasSuffix("-transcript.md") || $0.lastPathComponent.hasSuffix("-notes.md")
            }
            var transcriptLookup: [String: (filename: String, content: String)] = [:]
            for transcriptURL in transcriptFiles {
                let filename = transcriptURL.lastPathComponent
                guard parseVideoTranscriptFilename(filename) != nil else { continue }
                let content = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
                if let parsed = parseVideoTranscriptFilename(filename) {
                    transcriptLookup[transcriptKey(baseName: parsed.baseName, timestamp: parsed.timestamp)] = (filename: filename, content: content)
                }
            }

            let textEntries: [LogEntry] = files.compactMap { fileURL in
                let filename = fileURL.lastPathComponent
                guard filename != "titles.json",
                      !filename.hasSuffix("-transcript.md"),
                      !filename.hasSuffix("-notes.md") else { return nil }
                guard let parsed = parseTextFilename(filename) else { return nil }
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                return LogEntry(
                    id: parsed.id,
                    filename: filename,
                    timestamp: parsed.timestamp,
                    previewText: previewText(from: content),
                    cachedContent: content,
                    kind: .text,
                    transcriptFilename: nil,
                    recordingDurationSeconds: nil
                )
            }

            let videoEntries: [LogEntry] = files.compactMap { fileURL in
                let filename = fileURL.lastPathComponent
                guard let parsed = parseVideoFilename(filename) else { return nil }

                let transcript = transcriptLookup[transcriptKey(baseName: parsed.baseName, timestamp: parsed.timestamp)]
                let transcriptContent = transcript?.content ?? ""
                let durationSeconds = recordingDurationSeconds(for: fileURL)
                return LogEntry(
                    id: parsed.id,
                    filename: filename,
                    timestamp: parsed.timestamp,
                    previewText: previewText(from: transcriptContent),
                    cachedContent: transcriptContent,
                    kind: .video,
                    transcriptFilename: transcript?.filename ?? defaultTranscriptFilename(forVideoFilename: filename),
                    recordingDurationSeconds: durationSeconds
                )
            }

            let loaded: [LogEntry] = (textEntries + videoEntries)
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.filename > rhs.filename
                }
                return lhs.timestamp > rhs.timestamp
            }

            entries = loaded

            if let first = entries.first {
                selectedEntryId = first.id
                text = first.cachedContent
            } else {
                createNewEntry()
            }
        } catch {
            print("Failed to load entries: \(error)")
            createNewEntry()
        }
    }
}

private extension LogEntry {
    static func createNew(with formatter: DateFormatter) -> LogEntry {
        let id = UUID()
        let timestamp = Date()
        let stamp = formatter.string(from: timestamp)
        return LogEntry(
            id: id,
            filename: "untitled-\(stamp).md",
            timestamp: timestamp,
            previewText: "",
            cachedContent: "",
            kind: .text,
            transcriptFilename: nil,
            recordingDurationSeconds: nil
        )
    }

    static func createVideoEntry(with formatter: DateFormatter, transcript: String, durationSeconds: Double?) -> LogEntry {
        let id = UUID()
        let timestamp = Date()
        let stamp = formatter.string(from: timestamp)
        let transcriptFilename = "untitled-\(stamp)-notes.md"
        let normalizedTranscript = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptPreview = normalizedTranscript.isEmpty
            ? ""
            : (normalizedTranscript.count > 90 ? String(normalizedTranscript.prefix(90)) + "..." : normalizedTranscript)
        return LogEntry(
            id: id,
            filename: "untitled-\(stamp).mov",
            timestamp: timestamp,
            previewText: transcriptPreview,
            cachedContent: transcript,
            kind: .video,
            transcriptFilename: transcriptFilename,
            recordingDurationSeconds: durationSeconds
        )
    }
}
