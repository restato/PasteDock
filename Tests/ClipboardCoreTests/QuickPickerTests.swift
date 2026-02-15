import ClipboardCore
import Foundation
import Testing

@Test
func quickPickerMapsKeyboardCommands() {
    let mapper = QuickPickerKeyMapper()

    #expect(mapper.command(for: KeyInput(key: "1")) == .selectIndex(0))
    #expect(mapper.command(for: KeyInput(key: "9")) == .selectIndex(8))
    #expect(mapper.command(for: KeyInput(key: "enter")) == .executeTopResult)
    #expect(mapper.command(for: KeyInput(key: "escape")) == .close)
    #expect(mapper.command(for: KeyInput(key: "backspace", modifiers: [.command])) == .deleteSelection)
}

@Test
func quickPickerEntryIsOneLine() {
    let item = ClipboardItem(
        kind: .text,
        previewText: "line1\nline2",
        contentHash: "h",
        byteSize: 10,
        sourceBundleId: nil,
        payloadPath: "p"
    )

    let entry = QuickPickerEntry.from(item: item)
    #expect(entry.displayText == "line1 line2")
    #expect(entry.payloadPath == "p")
}
