import AppKit
import Foundation
import PropertyBased
import Testing

@testable import Waveform

private func trackPeaks() -> [Float] {
    (0..<WaveformData.columnCount).map { index in
        index == 1234 ? 1.0 : Float(index % 97) / 200
    }
}

@Test("Сжатие волны в один пиксель даёт энергетическое среднее колонок, а не самый громкий столбик")
func resampleToSinglePixelAveragesEnergy() {
    let peaks = trackPeaks()

    let result = WaveformResampler.resample(peaks, toWidth: 1)

    let meanSquare = peaks.reduce(Float(0)) { $0 + $1 * $1 } / Float(peaks.count)
    #expect(result.count == 1)
    #expect(abs(result[0] - meanSquare.squareRoot()) < 1e-5)
    // Прежний пик 1,0 рисовал всю полосу от верха до низа - теперь пиксель это среднее (≈ 0,278).
    #expect(result[0] < 0.5)
}

@Test("Сжатие двух колонок в пиксель считает RMS, а не максимум")
func resampleOfTwoColumnsIsRootMeanSquare() {
    let result = WaveformResampler.resample([1, 0], toWidth: 1)

    #expect(abs(result[0] - Float(0.5).squareRoot()) < 1e-6)  // √0,5 ≈ 0,707, а не 1,0
}

@Test("Растяжение волны шире исходных колонок не теряет максимум и не выходит за диапазон")
func resampleToWideWidthKeepsMaximum() {    let peaks = trackPeaks()

    let result = WaveformResampler.resample(peaks, toWidth: 5000)

    #expect(result.count == 5000)
    #expect(result.max() == peaks.max())
    #expect(result.min()! >= peaks.min()!)
}

@Test("Пустая волна даёт пустой результат при любой ширине")
func resampleOfEmptyWaveformIsEmpty() {
    #expect(WaveformResampler.resample([], toWidth: 800).isEmpty)
    #expect(WaveformResampler.resample(trackPeaks(), toWidth: 0).isEmpty)
}

@Test("Для любой ширины длина результата равна ширине, значения остаются в 0…1")
func resampleKeepsWidthAndRange() async {
    let peaks = trackPeaks()

    await propertyCheck(count: 50, input: Gen.int(in: 1...6000)) { width in
        let result = WaveformResampler.resample(peaks, toWidth: width)

        #expect(result.count == width)
        #expect(result.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

@MainActor
@Test("Смена стиля и размера перерисовывает волну, прогресс остаётся в 0…1")
func styleChangeRebuildsWaveform() {
    let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 500, height: 94))
    view.data = WaveformData(columns: (0..<WaveformData.columnCount).map { index in
        WaveformData.Column(low: Float(index % 50) / 50, mid: 0.2, high: 0.1)
    })
    view.layoutSubtreeIfNeeded()

    var style = WaveformStyle.default
    style.compression = .logarithmic(floorDb: -48)
    style.smoothingRadius = 0
    style.playedBrightness = 0.8
    view.style = style
    view.progress = 0.5
    view.layoutSubtreeIfNeeded()

    #expect(view.progress == 0.5)
    #expect(view.style == style)
}

@MainActor
@Test("Прогресс вне 0…1 прижимается к краям волны")
func progressIsClamped() {
    let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 500, height: 94))

    view.progress = -0.5
    #expect(view.progress == 0)

    view.progress = 3
    #expect(view.progress == 1)

    view.progress = 0.25
    #expect(view.progress == 0.25)
}

// MARK: - Паста drag-out: рецепт общий с обложкой в шапке

@Test("Паста drag-out несёт .fileURL, который Finder и DAW читают как файл")
func dragPasteboardCarriesFileURL() {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "Artist - Title.aiff")
    let item = WaveformView.pasteboardItem(for: url)

    #expect(item.string(forType: .fileURL) == url.absoluteString)

    let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.shima.claimp.t13a-drag-test"))
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([item]))
    let read = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL]
    #expect(read?.map { $0 as URL } == [url])
}

@MainActor
@Test("Волна без данных не падает и показывает пустое состояние")
func viewWithoutDataStaysEmpty() {
    let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 500, height: 94))
    view.layoutSubtreeIfNeeded()

    #expect(view.data == nil)

    view.data = WaveformData(columns: (0..<WaveformData.columnCount).map { index in
        WaveformData.Column(low: Float(index % 50) / 50, mid: 0, high: 0)
    })
    view.duration = 194
    view.progress = 0.5
    view.layoutSubtreeIfNeeded()

    #expect(view.data?.columns.count == WaveformData.columnCount)
}
