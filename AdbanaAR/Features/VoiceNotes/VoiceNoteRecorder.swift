import AVFoundation
import Foundation
import Observation
import Speech

/// Graba notas de voz (AVAudioRecorder, AAC mono, máx. 30 s) con autorización explícita
/// del micrófono, y opcionalmente las transcribe con Speech para completar `notas`.
@MainActor
@Observable
final class VoiceNoteRecorder: NSObject {
    enum Estado: Equatable { case inactivo, sinPermiso, grabando, grabado, reproduciendo, transcribiendo }

    static let duracionMaxima: TimeInterval = 30
    static var directorio: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NotasVoz", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private(set) var estado: Estado = .inactivo
    private(set) var nivel: Float = 0
    private(set) var segundos: TimeInterval = 0
    private(set) var archivo: String?
    private(set) var transcripcion: String?
    var error: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func solicitarPermiso() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: estado = .sinPermiso; return false
        default:
            let ok = await AVAudioApplication.requestRecordPermission()
            if !ok { estado = .sinPermiso }
            return ok
        }
    }

    func iniciar() async {
        guard await solicitarPermiso() else {
            error = "Sin permiso de micrófono. Actívalo en Ajustes > Adbana AR."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let nombre = "nota-\(UUID().uuidString.lowercased()).m4a"
            let url = Self.directorio.appendingPathComponent(nombre)
            let ajustes: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                AVEncoderBitRateKey: 32_000,
            ]
            let r = try AVAudioRecorder(url: url, settings: ajustes)
            r.isMeteringEnabled = true
            r.delegate = self
            guard r.record(forDuration: Self.duracionMaxima) else { throw NSError(domain: "audio", code: 1) }
            recorder = r
            if let previo = archivo { try? FileManager.default.removeItem(at: Self.directorio.appendingPathComponent(previo)) }
            archivo = nombre
            transcripcion = nil
            estado = .grabando
            error = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            self.error = "No se pudo iniciar la grabación."
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        nivel = max(0, min(1, (db + 50) / 50))
        segundos = recorder.currentTime
    }

    func detener() {
        recorder?.stop()
        finalizarGrabacion()
    }

    fileprivate func finalizarGrabacion() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        nivel = 0
        if estado == .grabando { estado = .grabado }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reproducir() {
        guard let archivo else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: Self.directorio.appendingPathComponent(archivo))
            player?.delegate = self
            player?.play()
            estado = .reproduciendo
        } catch { self.error = "No se pudo reproducir la nota." }
    }

    func detenerReproduccion() {
        player?.stop()
        player = nil
        estado = archivo == nil ? .inactivo : .grabado
    }

    /// Transcribe en español (Perú). Requiere permiso de reconocimiento de voz.
    func transcribir() async {
        guard let archivo else { return }
        let auth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized else {
            error = "Sin permiso de reconocimiento de voz: la nota se conserva como audio."
            return
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "es-PE")) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES")),
              rec.isAvailable else {
            error = "El reconocimiento de voz no está disponible ahora."
            return
        }
        estado = .transcribiendo
        let req = SFSpeechURLRecognitionRequest(url: Self.directorio.appendingPathComponent(archivo))
        req.shouldReportPartialResults = false
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        let texto: String? = await withCheckedContinuation { c in
            var reanudado = false
            rec.recognitionTask(with: req) { result, err in
                guard !reanudado else { return }
                if let result, result.isFinal { reanudado = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if err != nil { reanudado = true; c.resume(returning: nil) }
            }
        }
        transcripcion = texto.map { String($0.prefix(500)) }
        if texto == nil { error = "No se pudo transcribir la nota." }
        estado = .grabado
    }

    func descartar() {
        detenerReproduccion()
        if let archivo { try? FileManager.default.removeItem(at: Self.directorio.appendingPathComponent(archivo)) }
        archivo = nil
        transcripcion = nil
        segundos = 0
        estado = .inactivo
    }
}

extension VoiceNoteRecorder: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finalizarGrabacion() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.detenerReproduccion() }
    }
}
