import SwiftUI
import AppKit

// Add a global player instance for access throughout the app
let sharedAudioPlayer = AudioPlayerManager()

// Корневое представление для управления переходом между экранами
struct MainView: View {
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            ContentView()
                .opacity(showSplash ? 0 : 1)
            
            if showSplash {
                SplashScreen(isActive: $showSplash)
            }
        }
    }
}

// Экран загрузки
struct SplashScreen: View {
    @State private var pulsate = false
    @Binding var isActive: Bool
    
    var body: some View {
        ZStack {
            Color.white
            
            VStack(spacing: 20) {
                Image(systemName: "radio")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .scaleEffect(pulsate ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.3)
                            .repeatForever(autoreverses: true),
                        value: pulsate
                    )
                
                Text("Radio")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            pulsate = true
            
            // Переход к основному экрану через 2 секунды
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.7)) {
                    self.isActive = false
                }
            }
        }
    }
}

@main
struct Radio: App {
    @NSApplicationDelegateAdaptor private var appDelegate: RadioAppDelegate
    @StateObject private var player = sharedAudioPlayer
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(notificationManager)
                .frame(minWidth: 400, minHeight: 600)
                .modifier(BackgroundModifier())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 650)
        .defaultPosition(.center)
        .commands {
            // Скрываем стандартные пункты меню
            CommandGroup(replacing: .appInfo) {
                Button("About Radio") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Quit Radio") {
                    NSApplication.shared.terminate(nil)
                }
            }
            
            // Скрываем меню File, Edit, View и другие
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .textEditing) { }
            CommandGroup(replacing: .textFormatting) { }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .toolbar) { }
            CommandGroup(replacing: .sidebar) { }
        }
    }
}

// Модификатор для применения правильного фона в зависимости от версии macOS
struct BackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.thickMaterial, for: .window)
        } else {
            content.background(.thickMaterial)
        }
    }
}

class RadioAppDelegate: NSObject, NSApplicationDelegate {
    private let player = sharedAudioPlayer
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestAuthorization()
        
        // Set app to continue running when all windows are closed
        NSApp.setActivationPolicy(.regular)
    }
    
    // Prevent app from terminating when window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // Add menu item to show window if it's closed
    func applicationDidBecomeActive(_ notification: Notification) {
        // Show window if there are no visible windows when app is activated
        if NSApp.windows.filter({ $0.isVisible }).isEmpty {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    
    // Add dock menu for playback control
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        
        // Play/Pause menu item
        let playPauseTitle = player.isPlaying ? "Pause" : "Play"
        let playPauseItem = NSMenuItem(title: playPauseTitle, action: #selector(togglePlayback), keyEquivalent: "")
        playPauseItem.target = self
        menu.addItem(playPauseItem)
        
        // Show player menu item
        let showPlayerItem = NSMenuItem(title: "Show Player", action: #selector(showPlayer), keyEquivalent: "")
        showPlayerItem.target = self
        menu.addItem(showPlayerItem)
        
        return menu
    }
    
    @objc private func togglePlayback() {
        if player.isPlaying {
            player.stop()
        } else {
            player.play()
        }
    }
    
    @objc private func showPlayer() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
} 
