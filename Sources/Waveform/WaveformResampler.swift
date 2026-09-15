import Foundation

/// Сжатие готовой волны под ширину экрана. Чистая функция: ресайз окна пересчитывает только пиксели,
/// повторный анализ трека не нужен.
public enum WaveformResampler {
    /// Энергетическое среднее колонок, попавших в пиксель: `sqrt(mean(x²))`, а не максимум.
    /// Максимум на пикселе добивал бы провалы, которые пережили RMS-анализ, и волна снова
    /// становилась бы ровной полосой. Длина результата всегда равна `width`.
    /// Ширина <= 0 или пустой вход дают пустой массив; при входе 0…1 значения остаются в 0…1.
    public static func resample(_ columns: [Float], toWidth width: Int) -> [Float] {
        guard width > 0, !columns.isEmpty else { return [] }

        let count = columns.count
        var result = [Float]()
        result.reserveCapacity(width)

        for pixel in 0..<width {
            let start = pixel * count / width
            let end = max(start + 1, (pixel + 1) * count / width)
            var sumOfSquares: Float = 0
            for index in start..<end { sumOfSquares += columns[index] * columns[index] }
            result.append((sumOfSquares / Float(end - start)).squareRoot())
        }
        return result
    }
}
