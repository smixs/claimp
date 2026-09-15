import Testing

@testable import Waveform

private func makeWaveform(_ count: Int) -> WaveformData {
    let columns = (0..<count).map { index in
        WaveformData.Column(low: Float(index), mid: 0, high: 0)
    }
    return WaveformData(columns: columns)
}

@Test("Курсор за границами волны берёт крайние колонки")
func columnAtProgressClamps() {
    let waveform = makeWaveform(10)

    #expect(waveform.column(atProgress: -1)?.low == 0)
    #expect(waveform.column(atProgress: 2)?.low == 9)
}

@Test("У пустой волны колонки под курсором нет")
func emptyWaveformHasNoColumn() {
    let waveform = WaveformData(columns: [])

    #expect(waveform.column(atProgress: 0.5) == nil)
}

@Test("Высота столбика - самая громкая из трёх полос")
func columnPeakTakesLoudestBand() {
    let column = WaveformData.Column(low: 0.2, mid: 0.7, high: 0.4)

    #expect(column.peak == 0.7)
}
