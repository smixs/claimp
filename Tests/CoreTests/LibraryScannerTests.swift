import Darwin
import Foundation
import Testing

@testable import Core

@Test("Год 1994 читается из всех четырёх тегированных фикстур")
func taggedFixturesGive1994() async {
    let scanner = LibraryScanner()
    for name in ["id3v23.mp3", "id3v24.mp3", "tagged.flac", "tagged.m4a"] {
        let track = await scanner.track(at: Fixtures.url(name))
        #expect(track?.year == 1994, "год не 1994 в \(name)")
    }
}

@Test("Файл без года даёт nil, пустую ячейку и нет обложки")
func untaggedWavHasNoYear() async {
    let scanner = LibraryScanner()
    let track = await scanner.track(at: Fixtures.url("tone.wav"))
    #expect(track?.year == nil)
    #expect(track?.displayYear == "")
    #expect(track?.artwork == nil)
}

@Test("Обложка читается из тега MP3 и FLAC")
func artworkFromTags() async {
    let scanner = LibraryScanner()
    #expect(await scanner.track(at: Fixtures.url("id3v23.mp3"))?.artwork != nil)
    #expect(await scanner.track(at: Fixtures.url("tagged.flac"))?.artwork != nil)
}

@Test("Формат MP3 нормализуется, битрейт и частота на месте")
func mp3PropertiesMapped() async {
    let scanner = LibraryScanner()
    let track = await scanner.track(at: Fixtures.url("id3v23.mp3"))
    #expect(track?.format == "MP3")
    #expect(track?.bitrate == 320)
    #expect(track?.sampleRate == 44100)
    #expect((track?.duration ?? 0) > 0)
}

@Test("Пустой title в теге заменяется именем файла")
func emptyTitleFallsBackToFilename() async {
    let scanner = LibraryScanner()
    let track = await scanner.track(at: Fixtures.url("tone.wav"))
    #expect(track?.title == "tone")
}

@Test("Нечитаемый файл и не-аудио дают nil, а не падение")
func unreadableAndNonAudioGiveNil() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let garbage = dir.appendingPathComponent("garbage.mp3")
    FileManager.default.createFile(
        atPath: garbage.path, contents: Data((0..<1024).map { _ in UInt8.random(in: 0...255) }))
    let text = dir.appendingPathComponent("notes.txt")
    try! "hello".write(to: text, atomically: true, encoding: .utf8)
    let scanner = LibraryScanner()
    #expect(await scanner.track(at: garbage) == nil)
    #expect(await scanner.track(at: text) == nil)
}

@Test("Скан папки с подпапкой: только аудио, порядок по имени, мусор пропущен")
func scanFolder() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sub = dir.appendingPathComponent("sub")
    try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try! FileManager.default.copyItem(at: Fixtures.url("tagged.flac"), to: dir.appendingPathComponent("02.flac"))
    try! FileManager.default.copyItem(at: Fixtures.url("tagged.m4a"), to: sub.appendingPathComponent("10.m4a"))
    try! FileManager.default.copyItem(at: Fixtures.url("tone.wav"), to: dir.appendingPathComponent("9.wav"))
    FileManager.default.createFile(
        atPath: dir.appendingPathComponent("broken.mp3").path,
        contents: Data((0..<512).map { _ in UInt8.random(in: 0...255) }))
    try! "notes".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let tracks = await LibraryScanner().scan(folder: dir)
    #expect(tracks.map(\.url.lastPathComponent) == ["02.flac", "9.wav", "10.m4a"])
}

@Test("Скан несуществующей папки даёт пусто, а не бросок")
func scanMissingFolderIsEmpty() async {
    let tracks = await LibraryScanner().scan(
        folder: URL(fileURLWithPath: "/nonexistent-claimp-\(UUID().uuidString)"))
    #expect(tracks.isEmpty)
}

@Test("Скан 50 файлов укладывается в секунду")
func scanFiftyFilesUnderSecond() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let sources = ["tagged.flac", "tagged.m4a", "tone.wav"]
    for i in 0..<50 {
        try! FileManager.default.copyItem(
            at: Fixtures.url(sources[i % sources.count]),
            to: dir.appendingPathComponent(String(format: "track-%02d.\(sources[i % sources.count].split(separator: ".").last!)", i)))
    }
    let start = Date()
    let tracks = await LibraryScanner().scan(folder: dir)
    let elapsed = Date().timeIntervalSince(start)
    print("SCAN50: \(tracks.count) файлов за \(String(format: "%.3f", elapsed)) с")
    #expect(tracks.count == 50)
    #expect(elapsed < 1.0)
}

@MainActor
@Test("Скан не считает обход папки на главном потоке")
func scanDoesNotEnumerateOnMainThread() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Длинный обход: две с половиной тысячи пустых записей (папок) с аудио-именем - они перебираются,
    // но отсеиваются по isRegularFile, - и пятьдесят настоящих файлов для проверки результата.
    for index in 0..<2500 {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(String(format: "filler-%05d.mp3", index)),
            withIntermediateDirectories: false)
    }
    for index in 0..<50 {
        try FileManager.default.linkItem(
            at: Fixtures.url("tone.wav"),
            to: dir.appendingPathComponent(String(format: "good-%03d.wav", index)))
    }

    // Сколько процессорного времени главного потока стоит сам обход: с этой цифрой сравниваем
    // то, что скан тратит на главном потоке. Первый обход - прогрев кэша каталога.
    _ = LibraryScanner.audioFiles(in: dir)
    let beforeEnumeration = mainThreadCPUNanoseconds()
    let urls = LibraryScanner.audioFiles(in: dir)
    let enumerationCPU = mainThreadCPUNanoseconds() - beforeEnumeration
    #expect(urls.count == 50)

    // Считаем процессорное время, а не секунды: на загруженной машине секунды врёт планировщик,
    // а процессорное время не зависит от того, когда потоку дали ядро.
    // Замер в два раунда с холостым окном: параллельно идут другие тесты, их работа на главном
    // акторе попадает и в рабочий, и в холостой замер, поэтому из разницы вычитается.
    var excess: [UInt64] = []
    for _ in 0..<3 {
        let started = Date()
        let beforeScan = mainThreadCPUNanoseconds()
        let tracks = await Task { @MainActor in await LibraryScanner().scan(folder: dir) }.value
        let scanCPU = mainThreadCPUNanoseconds() - beforeScan
        let scanWall = Date().timeIntervalSince(started)
        #expect(tracks.count == 50)

        let beforeIdle = mainThreadCPUNanoseconds()
        try await Task.sleep(for: .seconds(max(scanWall, 0.2)))
        let idleCPU = mainThreadCPUNanoseconds() - beforeIdle
        excess.append(scanCPU > idleCPU ? scanCPU - idleCPU : 0)
    }
    let least = excess.min() ?? 0
    print(String(
        format: "SCAN-CPU: обход %.0f мс процессорного времени главного потока, скан сверх холостого окна %.0f, %.0f и %.0f мс",
        Double(enumerationCPU) / 1e6, Double(excess[0]) / 1e6, Double(excess[1]) / 1e6, Double(excess[2]) / 1e6))
    // При дефекте (обход в задаче вызывающего) на главном потоке появляется весь обход.
    #expect(least * 2 < enumerationCPU)
}

/// Процессорное время текущего потока (user + system) в наносекундах. Нужно, чтобы отличить
/// работу на главном потоке от работы на чужом: секунды на загруженной машине не показательны.
private func mainThreadCPUNanoseconds() -> UInt64 {
    var info = thread_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let thread = mach_thread_self()
    defer { mach_port_deallocate(mach_task_self_, thread) }
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return UInt64(info.user_time.seconds + info.system_time.seconds) * 1_000_000_000
        + UInt64(info.user_time.microseconds + info.system_time.microseconds) * 1_000
}
