import Accelerate
import Foundation

/// Сырые уровни (RMS) трёх полос по колонкам: по одному значению на колонку в каждом массиве.
struct BandLevels: Sendable, Equatable {
    var low: [Float]
    var mid: [Float]
    var high: [Float]

    /// Сколько колонок посчитано.
    var count: Int { low.count }

    /// Первые `count` колонок: нужно отрезкам, которые обрезаются концом файла.
    func prefix(_ count: Int) -> BandLevels {
        guard count < self.count else { return self }
        return BandLevels(
            low: Array(low.prefix(count)), mid: Array(mid.prefix(count)), high: Array(high.prefix(count)))
    }
}

/// Полосовой разделитель волны: три фильтра 4-го порядка на границах 600 Гц и 4 кГц.
///
/// Алгоритм - из Mixxx (`src/analyzer/analyzerwaveform.cpp:179-183`: `Bessel4Low(600)`,
/// `Bessel4Band(600, 4000)`, `Bessel4High(4000)`, границы полос - константы `:18,20`). Код Mixxx
/// (GPL-2) не копировался: здесь те же порядок и границы, но секции Баттерворта - у него плоская
/// полоса и коэффициенты считаются аналитически, а меньший выброс Бесселя на нашей картинке не виден.
/// Отличие T11: Mixxx берёт на колонку максимум модуля (`:253-261`), у нас на колонку идёт RMS
/// (см. `PCMReader`): отлимитированный мастер с максимумом давал сплошную полосу без динамики.
///
/// Фильтры хранят состояние между кусками чтения, поэтому трек читается потоково и память
/// постоянна. Экземпляр живёт внутри одной задачи-читателя: состояние не потокобезопасно,
/// поэтому класс не `Sendable` и границы задач не пересекает.
final class BandSplitter {
    /// Нижняя граница полос, Гц: ниже - бас (`low`), выше - середина (`mid`).
    static let lowMidFrequency = 600.0
    /// Верхняя граница полос, Гц: выше - верх (`high`).
    static let midHighFrequency = 4_000.0

    /// Q двух секций Баттерворта 4-го порядка: плоская полоса, срез 24 дБ на октаву.
    private static let butterworthQs = [0.541_196_100_146_197, 1.306_562_964_876_377]
    /// Q одной секции Баттерворта 2-го порядка - для полосового фильтра середины.
    private static let singleSectionQ = 0.707_106_781_186_548

    private let lowFilter: BiquadCascade
    private let midFilter: BiquadCascade
    private let highFilter: BiquadCascade

    /// - Parameter sampleRate: частота файла; границы полос не подпускаем к Найквисту (телефонные 8 кГц).
    init(sampleRate: Double) {
        let lowMid = min(Self.lowMidFrequency, 0.45 * sampleRate)
        let midHigh = min(Self.midHighFrequency, 0.45 * sampleRate)
        lowFilter = BiquadCascade(
            coefficients: Self.butterworth(.lowpass, at: lowMid, sampleRate: sampleRate))
        // Середина - ФВЧ на 600 Гц последовательно с ФНЧ на 4 кГц: по секции на границу, 4-й порядок.
        midFilter = BiquadCascade(
            coefficients: Self.biquad(.highpass, at: lowMid, q: Self.singleSectionQ, sampleRate: sampleRate)
                + Self.biquad(.lowpass, at: midHigh, q: Self.singleSectionQ, sampleRate: sampleRate))
        highFilter = BiquadCascade(
            coefficients: Self.butterworth(.highpass, at: midHigh, sampleRate: sampleRate))
    }

    /// Фильтрует `count` сэмплов одного канала: три полосы кладутся в буферы вызывающего.
    func split(
        _ input: UnsafePointer<Float>,
        low: UnsafeMutablePointer<Float>,
        mid: UnsafeMutablePointer<Float>,
        high: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard count > 0 else { return }
        lowFilter.process(input: input, output: low, count: count)
        midFilter.process(input: input, output: mid, count: count)
        highFilter.process(input: input, output: high, count: count)
    }

    /// Тот же расчёт по массиву: тестам и коротким прогонам удобнее без указателей.
    func split(_ samples: [Float]) -> (low: [Float], mid: [Float], high: [Float]) {
        guard !samples.isEmpty else { return ([], [], []) }
        var low = samples
        var mid = samples
        var high = samples
        samples.withUnsafeBufferPointer { input in
            split(input.baseAddress!, low: &low, mid: &mid, high: &high, count: samples.count)
        }
        return (low, mid, high)
    }

    private enum Kind {
        case lowpass
        case highpass
    }

    /// Секции Баттерворта 4-го порядка: две biquad-секции подряд.
    private static func butterworth(_ kind: Kind, at frequency: Double, sampleRate: Double) -> [Double] {
        butterworthQs.flatMap { biquad(kind, at: frequency, q: $0, sampleRate: sampleRate) }
    }

    /// Одна biquad-секция по формулам RBJ (Audio EQ Cookbook) в форме `vDSP_biquad`:
    /// `b0, b1, b2, a1, a2` при знаменателе `1 + a1 z⁻¹ + a2 z⁻²`.
    private static func biquad(
        _ kind: Kind, at frequency: Double, q: Double, sampleRate: Double
    ) -> [Double] {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        let a1 = -2 * cosine / a0
        let a2 = (1 - alpha) / a0
        switch kind {
        case .lowpass:
            let b0 = (1 - cosine) / 2
            return [b0 / a0, (1 - cosine) / a0, b0 / a0, a1, a2]
        case .highpass:
            let b0 = (1 + cosine) / 2
            return [b0 / a0, -(1 + cosine) / a0, b0 / a0, a1, a2]
        }
    }
}

/// Каскад biquad-секций `vDSP_biquad` вместе с состоянием задержек: состояние переносится между
/// вызовами, поэтому куски чтения склеиваются без щелчков.
private final class BiquadCascade {
    private let setup: vDSP_biquad_Setup
    private var delay: [Float]

    /// - Parameter coefficients: по пять чисел на секцию - `b0, b1, b2, a1, a2`.
    init(coefficients: [Double]) {
        let sections = coefficients.count / 5
        guard sections > 0, let setup = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(sections)) else {
            preconditionFailure("vDSP_biquad rejected the coefficients: \(coefficients)")
        }
        self.setup = setup
        // Состояние: по две задержки на секцию плюс два служебных слова (так требует vDSP_biquad).
        self.delay = [Float](repeating: 0, count: 2 * sections + 2)
    }

    deinit {
        vDSP_biquad_DestroySetup(setup)
    }

    func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, count: Int) {
        delay.withUnsafeMutableBufferPointer { state in
            vDSP_biquad(setup, state.baseAddress!, input, 1, output, 1, vDSP_Length(count))
        }
    }
}
