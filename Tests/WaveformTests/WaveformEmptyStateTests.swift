import AppKit
import Foundation
import Testing

@testable import Waveform

/// Пустое состояние волны (SPEC §6.12): пока данных нет, по центру полосы идёт тонкая осевая линия.
/// Рисунок проверяется по битмапу: он детерминирован, а руками такое состояние не поймать.

/// Байты битмапа волны: RGBA по байту на канал (premultipliedLast sRGB).
private func pixelData(of image: CGImage) throws -> (bytes: [UInt8], rowBytes: Int, pixelBytes: Int) {
    let cfData = try #require(image.dataProvider?.data)
    return ([UInt8](Data(referencing: cfData as NSData)), image.bytesPerRow, image.bitsPerPixel / 8)
}

/// Строки, где есть непрозрачный пиксель: картинка волны накладывается на фон слоя,
/// значит нарисованное - это alpha > 0.
private func inkRows(of image: CGImage) throws -> [Int] {
    let (bytes, rowBytes, pixelBytes) = try pixelData(of: image)
    return (0..<image.height).filter { row in
        (0..<image.width).contains { column in bytes[row * rowBytes + column * pixelBytes + 3] > 0 }
    }
}

/// Цвет первого непрозрачного пикселя строки.
private func inkColor(in row: Int, of image: CGImage) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
    let (bytes, rowBytes, pixelBytes) = try pixelData(of: image)
    var column = 0
    while column < image.width, bytes[row * rowBytes + column * pixelBytes + 3] == 0 { column += 1 }
    let index = row * rowBytes + min(column, image.width - 1) * pixelBytes
    return (bytes[index], bytes[index + 1], bytes[index + 2])
}

@MainActor
@Test("Пустая волна рисует тонкую линию по центру, а не ровный фон")
func emptyWaveDrawsCenterLine() throws {
    let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 200, height: 94))
    let image = try #require(view.makeWaveImage(width: 200, height: 80))

    let rows = try inkRows(of: image)

    // До правки тут было пусто: пустой профиль возвращал ровно прозрачный фон.
    #expect(!rows.isEmpty)
    // Линия - по центру полосы высотой 80, выше и ниже - фон.
    #expect(rows.allSatisfy { abs($0 - 40) <= 1 })

    // Цвет - токен emptyLine: линия не системного серого и не курсора.
    let expected = WaveformStyle.default.emptyLine
    let color = try inkColor(in: rows.first ?? 0, of: image)
    #expect(abs(Int(color.red) - Int((expected.red * 255).rounded())) <= 2)
    #expect(abs(Int(color.green) - Int((expected.green * 255).rounded())) <= 2)
    #expect(abs(Int(color.blue) - Int((expected.blue * 255).rounded())) <= 2)
}

@MainActor
@Test("С данными осевой линии нет: полоса рисует столбики, а не одну строку")
func waveWithDataIsNotJustACenterLine() throws {
    let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 200, height: 94))
    view.data = WaveformData(columns: (0..<WaveformData.columnCount).map { _ in
        WaveformData.Column(low: 0.9, mid: 0.9, high: 0.9)
    })
    let image = try #require(view.makeWaveImage(width: 200, height: 80))

    let rows = try inkRows(of: image)

    #expect(rows.count > 2)
}
