import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Waveform

/// Смок drag-out без рук: живой drag в Finder/DAW агенту недоступен, поэтому проверяем ровно тот
/// контракт, который читает drop-цель - публичную пасту с `public.file-url`.
/// Писатель строки плейлиста живёт в `Sources/App` (`PlaylistController.pasteboardItem`), у `App`
/// тест-таргета нет, поэтому шов берём у общего помощника `FilePasteboard.pasteboardItem(for:)`
/// (им же пользуется обложка в шапке): здесь живут живой файл, существование и тип.

/// Своя паста на каждый прогон: чужая (`general`) сделала бы тест зависимым от чужих данных.
private func dragPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("dev.shima.claimp.drag-smoke-\(UUID().uuidString)"))
}

@Test("Живой файл из пасты drag-out читается как NSURL, лежит на диске и остаётся аудио")
func draggedFileReadsBackAsLiveAudioFile() throws {
    let directory = try AudioFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Имя как у настоящих треков: пробелы, скобки, кириллица - их глотает percent-кодинг.
    let url = directory.appending(path: "Poppy - Lowlife (радио версия).wav")
    try AudioFixture.writeTone(seconds: 0.05, amplitude: 0.5, to: url)

    let item = FilePasteboard.pasteboardItem(for: url)
    #expect(item.types.contains(.fileURL))
    #expect(NSPasteboard.PasteboardType.fileURL.rawValue == UTType.fileURL.identifier)

    let pasteboard = dragPasteboard()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([item]))

    let read = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL]
    let readURL = try #require(read?.first as URL?)
    #expect(readURL == url)
    #expect(readURL.isFileURL)
    #expect(FileManager.default.fileExists(atPath: readURL.path))
    #expect(UTType(filenameExtension: readURL.pathExtension)?.conforms(to: .audio) == true)
}

@Test("Паста без public.file-url файла не отдаёт: drop-цель получает не URL")
func pasteboardWithoutFileURLYieldsNoURL() {
    let item = NSPasteboardItem()
    item.setString("Poppy - Lowlife", forType: .string)

    let pasteboard = dragPasteboard()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([item]))

    let read = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL]
    #expect((read ?? []).isEmpty)
}
