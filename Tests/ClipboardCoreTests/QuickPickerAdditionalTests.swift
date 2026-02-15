import ClipboardCore
import Testing

@Test
func quickPickerEntryKeepsImagePreviewText() {
    let item = ClipboardItem(
        kind: .image,
        previewText: "[Image] 12 KB",
        contentHash: "img",
        byteSize: 12_000,
        sourceBundleId: nil,
        payloadPath: "image.dat"
    )

    let entry = QuickPickerEntry.from(item: item)
    #expect(entry.displayText == "[Image] 12 KB")
}

@Test
func quickPickerEntryKeepsTextPayloadPath() {
    let item = ClipboardItem(
        kind: .text,
        previewText: "hello",
        contentHash: "text-payload",
        byteSize: 5,
        sourceBundleId: nil,
        payloadPath: "texts/hello.txt"
    )

    let entry = QuickPickerEntry.from(item: item)
    #expect(entry.payloadPath == "texts/hello.txt")
}

@Test
func quickPickerMapperReturnsNoneForUnmappedInput() {
    let mapper = QuickPickerKeyMapper()

    #expect(mapper.command(for: KeyInput(key: "0")) == .none)
    #expect(mapper.command(for: KeyInput(key: "a", modifiers: [.command])) == .none)
}

@Test
func quickPickerEntryKeepsFilePayloadPath() {
    let item = ClipboardItem(
        kind: .file,
        previewText: "[File] report.pdf",
        contentHash: "file",
        byteSize: 42,
        sourceBundleId: "com.apple.finder",
        payloadPath: "files/report.json"
    )

    let entry = QuickPickerEntry.from(item: item)
    #expect(entry.kind == .file)
    #expect(entry.payloadPath == "files/report.json")
}

@Test
func quickPickerEntryUsesKnownSourcePresentation() {
    let item = ClipboardItem(
        kind: .text,
        previewText: "value",
        contentHash: "source-known",
        byteSize: 1,
        sourceBundleId: "com.apple.Safari",
        payloadPath: "p"
    )

    let entry = QuickPickerEntry.from(
        item: item,
        sourcePresentation: SourcePresentation(appName: "Safari", timeText: "11:32", isKnownSource: true)
    )

    #expect(entry.sourceAppName == "Safari")
    #expect(entry.sourceTimeText == "11:32")
}

@Test
func quickPickerEntryUsesUnknownSourcePresentation() {
    let item = ClipboardItem(
        kind: .text,
        previewText: "value",
        contentHash: "source-unknown",
        byteSize: 1,
        sourceBundleId: nil,
        payloadPath: "p"
    )

    let entry = QuickPickerEntry.from(
        item: item,
        sourcePresentation: SourcePresentation(appName: "Unknown app", timeText: "11:33", isKnownSource: false)
    )

    #expect(entry.sourceAppName == nil)
    #expect(entry.sourceTimeText == "11:33")
}
