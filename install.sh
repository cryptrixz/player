#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"

pkill -f "kitty123-app" 2>/dev/null || true
pkill -f "electron" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

cat > "$INSTALL_DIR/main.swift" << 'SWIFTOF'
import AppKit
import Foundation

class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hasShadow = false
    }
}

class WaveView: NSView {
    var barViews: [NSView] = []
    var isAnimating: Bool = false
    var timer: Timer?
    var currentColor: NSColor = .white {
        didSet {
            for bv in barViews {
                bv.layer?.backgroundColor = currentColor.cgColor
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        
        for i in 0..<5 {
            let bv = NSView(frame: NSRect(x: CGFloat(i) * (barWidth + gap), y: 0, width: barWidth, height: 4))
            bv.wantsLayer = true
            bv.layer?.backgroundColor = currentColor.cgColor
            bv.layer?.cornerRadius = 1
            self.addSubview(bv)
            barViews.append(bv)
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func setPlaying(_ playing: Bool) {
        isAnimating = playing
        if playing {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    self?.animateBars()
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
            for bv in barViews {
                bv.frame.size.height = 4
                bv.frame.origin.y = 0
            }
        }
    }
    
    private func animateBars() {
        for bv in barViews {
            let h = CGFloat.random(in: 4...18)
            bv.frame.size.height = h
            bv.frame.origin.y = (20 - h) / 2
        }
    }
}

class OverlayViewController: NSViewController {
    let boxView = NSView()
    let artView = NSImageView()
    let trackLabel = NSTextField(labelWithString: "Connecting...")
    let artistLabel = NSTextField(labelWithString: "")
    let playPauseBtn = NSButton(title: "||", target: nil, action: nil)
    let nextBtn = NSButton(title: ">|", target: nil, action: nil)
    let prevBtn = NSButton(title: "|<", target: nil, action: nil)
    let progressBg = NSView()
    let progressFill = NSView()
    let waveView = WaveView(frame: NSRect(x: 390, y: 30, width: 25, height: 20))
    
    var totalDuration: Double = 1.0
    var currentPosition: Double = 0.0
    var isPlaying: Bool = false
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 80))
        
        boxView.frame = self.view.bounds
        boxView.wantsLayer = true
        boxView.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.88).cgColor
        boxView.layer?.cornerRadius = 18
        boxView.layer?.borderWidth = 1
        boxView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.22).cgColor
        self.view.addSubview(boxView)
        
        artView.frame = NSRect(x: 12, y: 12, width: 56, height: 56)
        artView.wantsLayer = true
        artView.layer?.cornerRadius = 12
        artView.imageScaling = .imageScaleProportionallyUpOrDown
        boxView.addSubview(artView)
        
        trackLabel.frame = NSRect(x: 80, y: 42, width: 300, height: 20)
        trackLabel.font = .systemFont(ofSize: 14, weight: .bold)
        trackLabel.textColor = .white
        boxView.addSubview(trackLabel)
        
        artistLabel.frame = NSRect(x: 80, y: 22, width: 300, height: 18)
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        boxView.addSubview(artistLabel)
        
        prevBtn.frame = NSRect(x: 80, y: 2, width: 30, height: 18)
        prevBtn.isBordered = false
        prevBtn.target = self
        prevBtn.action = #selector(doPrev)
        boxView.addSubview(prevBtn)
        
        playPauseBtn.frame = NSRect(x: 115, y: 2, width: 30, height: 18)
        playPauseBtn.isBordered = false
        playPauseBtn.target = self
        playPauseBtn.action = #selector(doPlayPause)
        boxView.addSubview(playPauseBtn)
        
        nextBtn.frame = NSRect(x: 150, y: 2, width: 30, height: 18)
        nextBtn.isBordered = false
        nextBtn.target = self
        nextBtn.action = #selector(doNext)
        boxView.addSubview(nextBtn)
        
        progressBg.frame = NSRect(x: 190, y: 8, width: 240, height: 4)
        progressBg.wantsLayer = true
        progressBg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        progressBg.layer?.cornerRadius = 2
        boxView.addSubview(progressBg)
        
        progressFill.frame = NSRect(x: 0, y: 0, width: 0, height: 4)
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.white.cgColor
        progressFill.layer?.cornerRadius = 2
        progressBg.addSubview(progressFill)
        
        boxView.addSubview(waveView)
        
        let gesture = NSClickGestureRecognizer(target: self, action: #selector(doScrub(_:)))
        progressBg.addGestureRecognizer(gesture)
    }
    
    @objc func doPlayPause() { runAppleScript("tell application \"Spotify\" to playpause") }
    @objc func doNext() { runAppleScript("tell application \"Spotify\" to next track") }
    @objc func doPrev() { runAppleScript("tell application \"Spotify\" to previous track") }
    
    @objc func doScrub(_ sender: NSClickGestureRecognizer) {
        let loc = sender.location(in: progressBg)
        let pct = max(0.0, min(1.0, loc.x / progressBg.bounds.width))
        let target = pct * totalDuration
        runAppleScript("tell application \"Spotify\" to set player position to \(target)")
    }
    
    func runAppleScript(_ cmd: String) {
        if let script = NSAppleScript(source: cmd) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
    
    func updateData(track: String, artist: String, duration: Double, position: Double, status: String, artPath: String) {
        trackLabel.stringValue = track
        artistLabel.stringValue = artist
        totalDuration = duration
        currentPosition = position
        isPlaying = (status == "playing")
        playPauseBtn.title = isPlaying ? "||" : "|>"
        waveView.setPlaying(isPlaying)
        
        let pct = totalDuration > 0 ? min(1.0, currentPosition / totalDuration) : 0.0
        progressFill.frame.size.width = pct * progressBg.bounds.width
        
        if !artPath.isEmpty, let img = NSImage(contentsOfFile: artPath) {
            artView.image = img
            if let targetColor = extractDominantColor(from: img) {
                waveView.currentColor = targetColor
            } else {
                waveView.currentColor = .white
            }
        } else {
            artView.image = nil
            waveView.currentColor = .white
        }
    }
    
    private func extractDominantColor(from image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let x = bitmap.pixelsWide / 2
        let y = bitmap.pixelsHigh / 2
        return bitmap.colorAt(x: x, y: y)
    }
}
SWIFTOF

#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
cd "$INSTALL_DIR"

cat > "$INSTALL_DIR/appdelegate.swift" << 'DELEGATEEOF'
import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: OverlayWindow!
    var controller: OverlayViewController!
    var trayItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainDisplay = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let winWidth: CGFloat = 450
        let winHeight: CGFloat = 80
        let xPos = (mainDisplay.width - winWidth) / 2
        let yPos = mainDisplay.minY + 20
        
        window = OverlayWindow(contentRect: NSRect(x: xPos, y: yPos, width: winWidth, height: winHeight))
        controller = OverlayViewController()
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        
        setupTray()
        startTrackingTimers()
    }
    
    func setupTray() {
        trayItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        trayItem.button?.title = "🎵"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Overlay", action: #selector(showWin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close Overlay", action: #selector(hideWin), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kitty123", action: #selector(quitApp), keyEquivalent: "q"))
        trayItem.menu = menu
    }
    
    @objc func showWin() { window.orderFront(nil) }
    @objc func hideWin() { window.orderOut(nil) }
    @objc func quitApp() { NSApp.terminate(nil) }
    
    func startTrackingTimers() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let script = """
            tell application "System Events"
                try
                    set frontApp to name of first application process whose frontmost is true
                    return frontApp
                on error
                    return ""
                end try
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                let res = appleScript.executeAndReturnError(&err).stringValue ?? ""
                let isRoblox = res.contains("Roblox") || res.contains("RobloxPlayer")
                
                DispatchQueue.main.async {
                    if isRoblox {
                        if !self.window.isVisible { self.window.orderFront(nil) }
                    } else {
                        if self.window.isVisible { self.window.orderOut(nil) }
                    }
                }
            }
        }
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard self.window.isVisible else { return }
            let script = """
            if application "Spotify" is running then
                tell application "Spotify"
                    try
                        set cTrack to current track
                        set trackName to name of cTrack
                        set artistName to artist of cTrack
                        set totalDur to duration of cTrack
                        set playerPos to player position
                        set pState to player state as string
                        
                        set cacheDir to POSIX path of (path to caches folder from user domain)
                        set artPath to cacheDir & "com.spotify.client/Artwork/"
                        
                        return trackName & "||" & artistName & "||" & totalDur & "||" & playerPos & "||" & pState & "||" & artPath
                    on error
                        return "No Track"
                    end try
                end tell
            end if
            return "No Track"
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                let res = appleScript.executeAndReturnError(&err).stringValue ?? "No Track"
                if res == "No Track" { return }
                
                let parts = res.components(separatedBy: "||")
                if parts.count >= 5 {
                    let track = parts
                    let artist = parts
                    let duration = (Double(parts) ?? 1000.0) / 1000.0
                    let position = Double(parts) ?? 0.0
                    let status = parts.lowercased()
                    let artwork = parts.count >= 6 ? parts : ""
                    
                    DispatchQueue.main.async {
                        self.controller.updateData(track: track, artist: artist, duration: duration, position: position, status: status, artPath: artwork)
                        self.trayItem.button?.title = "\(track) - \(artist)"
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
DELEGATEEOF

swiftc -O main.swift appdelegate.swift -o kitty123-app

mkdir -p kitty123.app/Contents/MacOS
mkdir -p kitty123.app/Contents/Resources
mv kitty123-app kitty123.app/Contents/MacOS/

cat > kitty123.app/Contents/Info.plist << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>kitty123-app</string>
    <key>CFBundleIdentifier</key>
    <string>com.kitty123.spotifyoverlay</string>
    <key>CFBundleName</key>
    <string>Kitty123</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLISTEOF

cat > make_icon.py << 'PYEOF'
import urllib.request
import os
import subprocess

try:
    img_url = "https://githubusercontent.com"
    urllib.request.urlretrieve(img_url, "source.png")
    
    os.makedirs("AppIcon.iconset", exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512]
    
    for s in sizes:
        subprocess.run(["sips", "-z", str(s), str(s), "source.png", "--out", f"AppIcon.iconset/icon_{s}x{s}.png"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if s * 2 <= 1024:
            subprocess.run(["sips", "-z", str(s*2), str(s*2), "source.png", "--out", f"AppIcon.iconset/icon_{s}x{s}@2x.png"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
    subprocess.run(["iconutil", "-c", "icns", "AppIcon.iconset"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.exists("AppIcon.icns"):
        os.rename("AppIcon.icns", "kitty123.app/Contents/Resources/AppIcon.icns")
except:
    pass
PYEOF

python3 make_icon.py 2>/dev/null || true
rm -rf AppIcon.iconset source.png make_icon.py

xattr -cr kitty123.app 2>/dev/null || true
codesign --force --deep --sign - kitty123.app/Contents/MacOS/kitty123-app 2>/dev/null || true

open kitty123.app
echo "Done. Native App compiled."
