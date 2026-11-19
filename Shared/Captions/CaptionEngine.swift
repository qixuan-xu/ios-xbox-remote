import Foundation
import Speech
import AVFoundation

/// 实时字幕：把游戏声音交给系统语音识别，按停顿分句；需要翻译的句子交给 CaptionTranslationHost 翻译。
@MainActor
final class CaptionEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case running
        case error(String)
    }

    /// 正在说的这句话（识别中，会不断变化）
    @Published private(set) var partial = ""
    /// 最近几句已经说完的话
    @Published private(set) var lines: [CaptionLine] = []
    @Published private(set) var status: Status = .idle
    /// 一段时间没有新内容就隐藏字幕
    @Published private(set) var isVisible = false

    private(set) var language: CaptionLanguage = .english

    /// 音频线程会直接把数据塞进当前的识别请求，所以单独加锁保存
    nonisolated let feeder = AudioFeeder()

    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var taskStart = Date()
    private var lastUpdate = Date()
    private var tickTimer: Timer?
    private var translationContinuation: AsyncStream<CaptionLine>.Continuation?
    /// 当前识别任务里已经定稿的字符数（同一个任务的识别结果是从头累积的）
    private var committedCount = 0

    // MARK: 启动 / 停止

    func start(language: CaptionLanguage) async {
        stop()
        self.language = language
        guard await Self.requestAuthorization() else {
            status = .error(String(localized: "没有语音识别权限，请在系统设置的「隐私与安全性 › 语音识别」里允许"))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable else {
            status = .error(String(localized: "这台设备暂不支持这种语言的语音识别"))
            return
        }
        self.recognizer = recognizer
        status = .running
        startTask()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        CaptionLog.log("开始识别 \(language.localeIdentifier)，设备端识别: \(recognizer.supportsOnDeviceRecognition)")
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        task?.cancel()
        task = nil
        feeder.setRequest(nil)
        recognizer = nil
        partial = ""
        lines = []
        isVisible = false
        if status == .running { status = .idle }
    }

    // MARK: 识别任务

    private func startTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.taskHint = .dictation
        // 让识别结果带标点，这样可以按句子断开，而不必等说话人停顿
        if #available(macOS 13.0, iOS 16.0, *) { request.addsPunctuation = true }
        committedCount = 0
        feeder.setRequest(request)
        taskStart = Date()
        lastUpdate = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.handle(transcript: text)
                    self.lastUpdate = Date()
                    self.isVisible = true
                }
                if isFinal { self.finalizeCurrent() }
                else if let error, (error as NSError).code != 216, (error as NSError).code != 301 {
                    // 216/301 是主动取消，不算错误
                    CaptionLog.log("识别出错: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 收到新的识别结果：去掉已经定稿的部分，遇到完整句子就先定稿
    private func handle(transcript: String) {
        // 识别器偶尔会改写前面的字，导致结果比已定稿的还短，这时重新对齐
        if transcript.count < committedCount { committedCount = transcript.count }
        var remainder = String(transcript.dropFirst(committedCount))
        while let cut = CaptionSegmenter.splitPoint(in: remainder) {
            let sentence = String(remainder.prefix(cut))
            commit(sentence)
            committedCount += cut
            remainder = String(remainder.dropFirst(cut))
        }
        partial = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let line = CaptionLine(original: text, translated: nil, finishedAt: Date())
        lines = CaptionSegmenter.trimmed(lines + [line])
        if language.needsTranslation { translationContinuation?.yield(line) }
    }

    /// 把当前这句定稿，并换一个新的识别任务继续听
    private func finalizeCurrent() {
        commit(partial)
        partial = ""
        task?.cancel()
        task = nil
        startTask()
    }

    private func tick() {
        let now = Date()
        if CaptionSegmenter.shouldFinalize(text: partial, lastUpdate: lastUpdate, taskStart: taskStart, now: now) {
            finalizeCurrent()
        }
        let visible = now.timeIntervalSince(lastUpdate) < 4
        if visible != isVisible { isVisible = visible }
    }

    // MARK: 翻译

    /// 翻译宿主每次（重新）开始时调用，拿到待翻译句子的队列；还没翻译的句子会重新放进去
    func makeTranslationStream() -> AsyncStream<CaptionLine> {
        translationContinuation?.finish()
        var captured: AsyncStream<CaptionLine>.Continuation?
        let stream = AsyncStream<CaptionLine> { captured = $0 }
        translationContinuation = captured
        for line in lines where line.translated == nil { captured?.yield(line) }
        return stream
    }

    func setTranslation(_ text: String, for id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translated = text
        lastUpdate = Date()
        isVisible = true
    }

    func translationFailed(_ error: Error) {
        CaptionLog.log("翻译失败: \(error.localizedDescription)")
    }

    // MARK: 权限

    private static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status == .authorized) }
            }
        }
    }
}

/// 线程安全地把音频送进当前识别请求
final class AudioFeeder {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        self.request?.endAudio()
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}

/// 字幕日志（在 Xcode 控制台里搜索 [Caption]）
enum CaptionLog {
    static func log(_ message: String) { print("[Caption] \(message)") }
}
