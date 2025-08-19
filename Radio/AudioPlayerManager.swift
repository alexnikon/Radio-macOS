//
//  AudioPlayerManager.swift
//  Radio
//
//  Created by Alex Nikon on 16.03.2025.
//

import AVFoundation
import Combine
import MediaPlayer
import AppKit

// Определяем имя для уведомления об обновлении Now Playing
extension Notification.Name {
    static let updateNowPlaying = Notification.Name("com.radio-t.updateNowPlaying")
}

enum StreamType: Int, CaseIterable {
    case wkncHD1
    case wkncHD2
    case radioT
    
    var url: URL {
        switch self {
        case .wkncHD1:
            return URL(string: "https://das-edge14-live365-dal02.cdnstream.com/a45877")!
        case .wkncHD2:
            return URL(string: "https://das-edge12-live365-dal02.cdnstream.com/a30009")!
        case .radioT:
            return URL(string: "https://stream.radio-t.com")!
        }
    }
    
    var title: String {
        switch self {
        case .wkncHD1: return "WKNC HD1"
        case .wkncHD2: return "WKNC HD2"
        case .radioT: return "Radio-T"
        }
    }
}

struct TrackInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var albumArt: Data? = nil
    
    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        return lhs.title == rhs.title && lhs.artist == rhs.artist
    }
}

class AudioPlayerManager: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentStream: StreamType = .wkncHD2
    @Published var currentTrackInfo: TrackInfo = TrackInfo()
    @Published var volume: Float = 1.0
    
    private let volumeDefaultsKey = "player.volume"
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataFetchTimer: Timer?
    private var metadataStreamTask: URLSessionDataTask?
    private var metadataBuffer = Data()
    
    override init() {
        super.init()
        // Load saved volume if present
        if UserDefaults.standard.object(forKey: volumeDefaultsKey) != nil {
            let saved = UserDefaults.standard.float(forKey: volumeDefaultsKey)
            volume = max(0.0, min(1.0, saved))
        }
        setupRemoteCommands()
        
        // По умолчанию используем WKNC HD2
        currentStream = .wkncHD2
        
        // Set up MediaPlayer framework commands for Now Playing
        setupMediaPlayerCommands()
        
        // Добавляем наблюдателя за уведомлением
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateNowPlaying),
            name: .updateNowPlaying,
            object: nil
        )
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        metadataFetchTimer?.invalidate()
        metadataStreamTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    // Configure audio session for background play
    private func configureAudioSession() {
        // Убираем условия для iOS, так как ориентируемся только на macOS 15
    }
    
    func switchStream(_ streamType: StreamType) {
        let wasPlaying = isPlaying
        stop()
        currentStream = streamType
        metadataStreamTask?.cancel()
        if wasPlaying {
            play()
        }
    }
    
    func playPause() {
        if player == nil {
            setupPlayer()
            return
        }
        isPlaying ? pause() : play()
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        metadataStreamTask?.cancel()
        
        // Update dock icon badge
        updateDockIconBadge()
        
        // Clear Now Playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Очищаем информацию о треке
        currentTrackInfo = TrackInfo()
    }
    
    // Метод вызывается только когда нажимается кнопка play при неактивном воспроизведении
    // или при stop и новом запуске
    func play() {
        isLoading = true
        errorMessage = nil
        
        // Для Radio-T проверяем доступность трансляции перед запуском
        if currentStream == .radioT && player == nil {
            preflightCheckRadioTLive { [weak self] isLive in
                guard let self else { return }
                DispatchQueue.main.async {
                    if isLive {
                        self.setupPlayer()
                    } else {
                        self.isLoading = false
                        self.isPlaying = false
                        self.errorMessage = "Трансляция еще не началась"
                    }
                }
            }
            return
        }
        
        if player == nil {
            setupPlayer()
        } else {
            player?.play()
            isPlaying = true
            isLoading = false
            
            // Update dock icon badge
            updateDockIconBadge()
            
            // Update Control Center Now Playing
            updateNowPlayingInfo()
            
            // Запускаем обновление метаданных при начале воспроизведения
            fetchMetadata()
        }
    }

    // Быстрый запрос для проверки, идет ли сейчас трансляция Radio-T
    private func preflightCheckRadioTLive(completion: @escaping (Bool) -> Void) {
        let url = StreamType.radioT.url
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("Radio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4.0
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Любая явная ошибка сети трактуем как неактивную трансляцию
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            // Принимаем 200/206 как признак доступности
            let okStatus = (200...206).contains(http.statusCode)
            if okStatus {
                completion(true)
                return
            }
            completion(false)
        }
        task.resume()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        
        // Update dock icon badge
        updateDockIconBadge()
        
        // Update Control Center Now Playing
        updateNowPlayingInfo()
    }
    
    private func setupPlayer() {
        isLoading = true
        errorMessage = nil
        currentTrackInfo = TrackInfo()
        
        let asset = AVURLAsset(url: currentStream.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "Radio/1.0 (macOS)"]
        ])
        
        Task {
            do {
                let playerItem = AVPlayerItem(asset: asset)
                
                // Настройка метаданных
                let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
                metadataOutput.setDelegate(self, queue: DispatchQueue.main)
                await playerItem.add(metadataOutput) // Убираем try, так как метод не выбрасывает исключений
                self.metadataOutput = metadataOutput
                
                // Создание плеера
                let player = AVPlayer(playerItem: playerItem)
                self.player = player
                // Применяем текущую громкость к новому плееру
                self.player?.volume = self.volume
                
                // Добавляем наблюдатель состояния
                self.addPlayerItemObserver(playerItem)
                
                // Добавляем наблюдатель времени для обновления метаданных
                let timeInterval = CMTime(seconds: 10, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                self.timeObserver = player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] _ in
                    self?.fetchMetadata()
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.play()
                }
            }
        }
    }
    
    private func addPlayerItemObserver(_ playerItem: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEndTime),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )
    }
    
    @objc private func playerItemDidPlayToEndTime() {
        // Действие при завершении воспроизведения
        print("Stream ended")
        
        // Пытаемся воспроизвести снова, так как потоковое вещание не должно заканчиваться
        setupPlayer()
    }
    
    @objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            errorMessage = "Playback failed: \(error.localizedDescription)"
            isPlaying = false
        }
    }
    
    @objc private func handleUpdateNowPlaying() {
        fetchMetadata()
    }
    
    // MARK: - Настройка удаленного управления (MediaPlayer)
    private func setupRemoteCommands() {
        // macOS не поддерживает MPRemoteCommandCenter как iOS
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Очищаем все команды
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        
        // Настраиваем команду воспроизведения
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.play()
            return .success
        }
        
        // Настраиваем команду паузы
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        // Настраиваем команду остановки
        commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.stop()
            return .success
        }
        
        // Настраиваем команду переключения воспроизведения/паузы
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playPause()
            return .success
        }
        #endif
    }
    
    // Setup MediaPlayer commands for Now Playing
    private func setupMediaPlayerCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Clear all previous handlers
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        
        // Add play command handler
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.play()
            return .success
        }
        
        // Add pause command handler
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        // Add stop command handler
        commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.stop()
            return .success
        }
        
        // Add toggle play/pause command handler
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playPause()
            return .success
        }
    }
    
    // MARK: - Методы работы с метаданными
    
    private func fetchMetadata() {
        // Отменяем предыдущий запрос
        metadataStreamTask?.cancel()
        
        // У Radio-T своя логика получения метаданных
        if currentStream == .radioT {
            fetchRadioTMetadata()
            return
        }
        
        // У WKNC используем SHOUTcast
        let metadataURL: URL
        if currentStream == .wkncHD1 {
            metadataURL = URL(string: "https://das-edge14-live365-dal02.cdnstream.com/a45877?type=.mp3?icy=http")!
        } else {
            metadataURL = URL(string: "https://das-edge12-live365-dal02.cdnstream.com/a30009?type=.mp3?icy=http")!
        }
        
        var request = URLRequest(url: metadataURL)
        request.setValue("Radio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.timeoutInterval = 15.0
        
        metadataStreamTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            
            guard error == nil else {
                DispatchQueue.main.async {
                    print("Metadata fetch error: \(error!)")
                }
                return
            }
            
            if let icyMetaInt = (response as? HTTPURLResponse)?.allHeaderFields["icy-metaint"] as? String,
               let metaInt = Int(icyMetaInt),
               let data {
                DispatchQueue.main.async {
                    self.parseShoutcastMetadata(data: data, metaInt: metaInt)
                }
            }
        }
        
        metadataStreamTask?.resume()
    }
    
    private func fetchRadioTMetadata() {
        guard let url = URL(string: "https://radio-t.com/site-api/last/5") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Radio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data, error == nil else {
                if let error {
                    print("Radio-T metadata fetch error: \(error)")
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let latestEpisode = json.first,
                   let title = latestEpisode["title"] as? String {
                    
                    DispatchQueue.main.async {
                        var trackInfo = TrackInfo()
                        trackInfo.title = "Radio"
                        trackInfo.artist = title
                        self.currentTrackInfo = trackInfo
                        
                        // Update Now Playing info when track info changes
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("Radio-T metadata parse error: \(error)")
            }
        }.resume()
    }
    
    private func parseShoutcastMetadata(data: Data, metaInt: Int) {
        guard metaInt > 0 else { return }
        
        // Буферизируем данные
        metadataBuffer.append(data)
        
        // Если у нас недостаточно данных, просто выходим
        if metadataBuffer.count < metaInt + 1 {
            return
        }
        
        // Получаем длину метаданных
        let metadataLengthByte = metadataBuffer[metaInt]
        let metadataLength = Int(metadataLengthByte) * 16
        
        // Если у нас недостаточно данных, просто выходим
        if metadataBuffer.count < metaInt + 1 + metadataLength {
            return
        }
        
        // Извлекаем метаданные
        if metadataLength > 0 {
            let metadataRange = (metaInt + 1)..<(metaInt + 1 + metadataLength)
            let metadataData = metadataBuffer.subdata(in: metadataRange)
            
            if let metadataString = String(data: metadataData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                parseMetadataString(metadataString)
            } else if let metadataString = String(data: metadataData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                parseMetadataString(metadataString)
            }
        }
        
        // Очищаем буфер
        metadataBuffer.removeAll()
        
        // Отменяем задачу, так как мы получили метаданные
        metadataStreamTask?.cancel()
    }
    
    private func parseMetadataString(_ metadataString: String) {
        // Ищем "StreamTitle='...'"
        let streamTitlePattern = "StreamTitle='([^']*)'"
        let titleRange = metadataString.range(of: streamTitlePattern, options: .regularExpression)
        
        if let titleRange = titleRange {
            let title = String(metadataString[titleRange])
                .replacingOccurrences(of: "StreamTitle='", with: "")
                .replacingOccurrences(of: "'", with: "")
            
            // Попытаемся разделить на исполнителя и название трека
            let components = title.components(separatedBy: " - ")
            
            DispatchQueue.main.async {
                var trackInfo = TrackInfo()
                
                if components.count > 1 {
                    trackInfo.artist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    trackInfo.title = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    trackInfo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                self.currentTrackInfo = trackInfo
                
                // Update Now Playing info when track info changes
                self.updateNowPlayingInfo()
            }
        }
    }
    
    // Установка громкости плеера и сохранение текущего значения
    func setVolume(_ value: Float) {
        let clamped = max(0.0, min(1.0, value))
        volume = clamped
        player?.volume = clamped
        UserDefaults.standard.set(clamped, forKey: volumeDefaultsKey)
    }
    
    // Add method to update dock icon badge
    private func updateDockIconBadge() {
        DispatchQueue.main.async {
            if self.isPlaying {
                NSApp.dockTile.badgeLabel = "▶"
            } else {
                NSApp.dockTile.badgeLabel = nil
            }
        }
    }
    
    // Update Now Playing info in Control Center
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        
        // Set title and artist
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrackInfo.title.isEmpty ? currentStream.title : currentTrackInfo.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentTrackInfo.artist.isEmpty ? "Radio" : currentTrackInfo.artist
        
        // Set album title to stream name
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentStream.title
        
        // Set playback state
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // Add default artwork if needed
        if let image = NSImage(systemSymbolName: "radio", accessibilityDescription: nil),
           let resizedImage = resizeImage(image, to: CGSize(width: 300, height: 300)),
           let tiffData = resizedImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [:]) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300)) { _ in
                if let nsImage = NSImage(data: jpegData) {
                    return nsImage
                }
                return NSImage()
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        // Update info in MPNowPlayingInfoCenter
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // Helper method to resize images for artwork
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage? {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), 
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // Метод для обновления информации о треке
    func updateTrackInfo(title: String) {
        // Парсим строку метаданных
        let components = title.components(separatedBy: " - ")
        
        var trackInfo = TrackInfo()
        if components.count > 1 {
            trackInfo.artist = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            trackInfo.title = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            trackInfo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        self.currentTrackInfo = trackInfo
        
        // Update Now Playing info when track info changes
        self.updateNowPlayingInfo()
    }
    
    // Обновленная реализация метода обработки метаданных
    @objc func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        // Синхронная версия метода для соответствия протоколу AVPlayerItemMetadataOutputPushDelegate
        Task {
            await metadataOutputAsync(output, didOutputTimedMetadataGroups: groups, from: track)
        }
    }
    
    // Асинхронная версия метода для обработки метаданных
    private func metadataOutputAsync(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) async {
        guard let group = groups.first, let metadata = group.items.first else { return }
        
        // Обработка метаданных используя современный API
        if let title = try? await metadata.load(.stringValue) {
            DispatchQueue.main.async { [weak self] in
                self?.updateTrackInfo(title: title)
            }
        }
    }
} 