import AVFoundation
import Foundation

/// Синтетический клик-трек с известным темпом: файл пишется во временную папку,
/// в репозитории аудиофикстур анализа не держим.
enum ClickTrack {
    static let sampleRate = 44_100.0

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "claimp-analysis-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Ровный клик: на каждую долю затухающий тон 180 Гц с щелчком в атаке, между долями тишина.
    @discardableResult
    static func write(bpm: Double, seconds: Double, to url: URL) throws -> URL {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let total = Int(seconds * sampleRate)
        let period = sampleRate * 60 / bpm
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(sampleRate))
        else { throw ClickTrackError.cannotWrite }
        var written = 0
        while written < total {
            let frames = min(Int(sampleRate), total - written)
            fill(buffer, frames: frames, firstFrame: written, period: period)
            try file.write(from: buffer)
            written += frames
        }
        return url
    }

    private static func fill(_ buffer: AVAudioPCMBuffer, frames: Int, firstFrame: Int, period: Double) {
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let channel = buffer.floatChannelData?[0] else { return }
        for index in 0..<frames {
            let position = Double(firstFrame + index)
            let sinceBeat = position.truncatingRemainder(dividingBy: period) / sampleRate
            channel[index] = Float(click(sinceBeat: sinceBeat))
        }
    }

    /// Один удар: 60 мс, экспоненциальное затухание, тон 180 Гц плюс высокий призвук атаки.
    private static func click(sinceBeat seconds: Double) -> Double {
        guard seconds < 0.06 else { return 0 }
        let envelope = exp(-seconds * 60)
        let body = sin(2 * .pi * 180 * seconds)
        let attack = seconds < 0.004 ? sin(2 * .pi * 3_000 * seconds) * 0.5 : 0
        return 0.8 * envelope * (body + attack)
    }
}

enum ClickTrackError: Error {
    case cannotWrite
}
