import AVFoundation
import Foundation

/// Живые аудиофайлы для тестов пишутся во временную папку: фикстур в репо не держим.
enum AudioFixture {
    static let sampleRate = 44100.0

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "claimp-waveform-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Синус 440 Гц заданной громкости; amplitude 0 - тишина. Размер файла зависит только от длины.
    @discardableResult
    static func writeTone(
        seconds: Double, amplitude: Float, frequency: Double = 440, to url: URL
    ) throws -> URL {
        try writeTone(
            seconds: seconds, amplitude: amplitude, frequency: frequency, toneSeconds: seconds, to: url)
    }

    /// Тот же синус, но с секунды `toneSeconds` - тишина: нужен проверкам RMS по колонкам,
    /// где одна колонка обязана попасть в тон, а другая в тишину.
    @discardableResult
    static func writeTone(
        seconds: Double, amplitude: Float, frequency: Double = 440, toneSeconds: Double, to url: URL
    ) throws -> URL {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        var written = 0
        let total = Int(seconds * sampleRate)
        let toneFrames = Int(toneSeconds * sampleRate)
        let chunk = min(total, Int(sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, chunk))) else {
            throw WaveformFixtureError.cannotWrite
        }
        while written < total {
            let frames = min(chunk, total - written)
            fill(
                buffer, frames: frames, firstFrame: written, amplitude: amplitude, frequency: frequency,
                toneFrames: toneFrames)
            try file.write(from: buffer)
            written += frames
        }
        return url
    }

    private static func fill(
        _ buffer: AVAudioPCMBuffer, frames: Int, firstFrame: Int, amplitude: Float, frequency: Double,
        toneFrames: Int
    ) {
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let channels = buffer.floatChannelData else { return }
        for index in 0..<frames {
            let phase = Float(2 * Double.pi * frequency * Double(firstFrame + index) / sampleRate)
            let value = firstFrame + index < toneFrames ? amplitude * sin(phase) : 0
            for channel in 0..<Int(buffer.format.channelCount) { channels[channel][index] = value }
        }
    }
}

enum WaveformFixtureError: Error {
    case cannotWrite
}
