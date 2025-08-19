//
//  ContentView.swift
//  Radio
//
//  Created by Alex Nikon on 16.03.2025.
//

import SwiftUI
import AVKit

struct ErrorBanner: View {
    let message: String
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack {
            if isVisible {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text(message)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.red.opacity(0.9))
                .cornerRadius(8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: isVisible)
    }
}

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var showError = false
    // Состояния для анимации эквалайзера
    @State private var barHeights: [CGFloat] = [0.4, 0.6, 0.5, 0.7, 0.3]
    @State private var timer: Timer? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // Заголовок с выбором потока
            HStack {
                Spacer()
                
                Picker("Stream", selection: $player.currentStream) {
                    ForEach(StreamType.allCases, id: \.self) { streamType in
                        Text(streamType.title).tag(streamType)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            
            // Основной контент
            VStack {
                Text(player.currentStream.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(.top, 20)
                
                // Отображение информации о треке
                if player.isPlaying {
                    VStack(spacing: 5) {
                        if !player.currentTrackInfo.title.isEmpty {
                            Text(player.currentTrackInfo.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                        }
                        
                        if !player.currentTrackInfo.artist.isEmpty {
                            Text(player.currentTrackInfo.artist)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                        } else if player.currentTrackInfo.title.isEmpty {
                            Text("Now Playing")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .animation(.easeInOut, value: player.currentTrackInfo)
                    
                    // Анимация эквалайзера
                    HStack(spacing: 4) {
                        ForEach(0..<5) { i in
                            Capsule()
                                .fill(Color.blue)
                                .frame(width: 3, height: 30 * barHeights[i])
                                .animation(
                                    .easeInOut(duration: 0.4),
                                    value: barHeights[i]
                                )
                        }
                    }
                    .frame(height: 30)
                    .padding(.vertical, 10)
                    .onAppear {
                        // Запускаем таймер для анимации эквалайзера
                        startEqualizerAnimation()
                    }
                    .onDisappear {
                        // Останавливаем таймер при исчезновении вида
                        stopEqualizerAnimation()
                    }
                }
                
                Spacer()
                
                // Сообщение над кнопкой, если трансляция Radio-T еще не началась
                if let error = player.errorMessage, error == "Трансляция еще не началась" {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }

                // Регулировка громкости
                HStack(spacing: 8) {
                    Button(action: { player.setVolume(0.0) }) {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Mute")
                    Slider(value: .init(
                        get: { Double(player.volume) },
                        set: { player.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 220)
                    Button(action: { player.setVolume(1.0) }) {
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Max volume")
                }
                .padding(.bottom, 8)

                // Кнопка Play/Stop
                Button(action: {
                    if player.isPlaying {
                        player.stop()
                    } else {
                        // Перед запуском воспроизведения убедимся, что будет использован текущий выбранный поток
                        player.switchStream(player.currentStream)
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 70)
                
                // Панель управления
                HStack(spacing: 30) {
                    if player.currentStream == .radioT {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://news.radio-t.com")!)
                        }) {
                            Image(systemName: "globe")
                                .font(.title2)
                            Text("Новости")
                        }
                        
                        Button(action: {
                            if let url = URL(string: "https://t.me/radio_t_chat") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "message.fill")
                                .font(.title2)
                            Text("Чат")
                        }
                    } else {
                        // Пустое пространство для резервирования высоты, 
                        // чтобы кнопка Play не меняла положение при переключении вкладок
                        Spacer()
                            .frame(height: 30) // Высота, примерно равная высоте кнопок
                    }
                }
                .frame(height: 30) // Фиксированная высота для всех состояний
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Дополнительный контейнер для ошибок (кроме сообщения о старте трансляции)
            if let error = player.errorMessage, error != "Трансляция еще не началась" {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
        }
        .onAppear {
            // Only set up initial stream if not already playing
            if !player.isPlaying && !player.isLoading {
                player.switchStream(player.currentStream)
            }
        }
    }
    
    // Функция для запуска анимации эквалайзера
    private func startEqualizerAnimation() {
        // Остановим предыдущий таймер, если он был
        stopEqualizerAnimation()
        
        // Запускаем новый таймер, который будет обновлять высоты полос
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Обновляем высоты всех полос случайными значениями
            for i in 0..<barHeights.count {
                // Генерируем случайное значение от 0.2 до 1.0
                barHeights[i] = CGFloat.random(in: 0.2...1.0)
            }
        }
    }
    
    // Функция для остановки анимации эквалайзера
    private func stopEqualizerAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    ContentView()
} 
