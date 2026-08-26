#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"

pkill -f "Electron" 2>/dev/null || true
pkill -f "kitty123" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

rm -rf kitty123.app
mkdir -p kitty123.app/Contents/MacOS
mkdir -p kitty123.app/Contents/Resources
mkdir -p kitty123.app/Contents/images

cat > kitty123.app/Contents/MacOS/applet << 'APPLETEOF'
#!/bin/bash
osascript -e '
on run
    repeat
        if application "Spotify" is running then
            tell application "Spotify"
                try
                    if player state is playing then
                        set trackName to name of current track
                        set artistName to artist of current track
                        set totalDur to (duration of current track) / 1000
                        set currentPos to player position
                        
                        set minNum to (currentPos div 60) as string
                        set secNum to (round (currentPos mod 60)) as string
                        if length of secNum is 1 then set secNum to "0" & secNum
                        
                        set totMin to (totalDur div 60) as string
                        set totSec to (round (totalDur mod 60)) as string
                        if length of totSec is 1 then set totSec to "0" & totSec
                        
                        set displayString to "🎵 " & trackName & " - " & artistName & " [" & minNum & ":" & secNum & " / " & totMin & ":" & totSec & "]"
                    else
                        set displayString to "⏸️ Spotify Paused"
                    end if
                on error
                    set displayString to "🎵 Spotify"
                end try
            end tell
        else
            set displayString to "Offline"
        end if
        
        tell application "System Events"
            try
                set frontAppName to name of first application process whose frontmost is true
                if frontAppName contains "Roblox" or frontAppName contains "RobloxPlayer" then
                    if displayString is not "Offline" then
                        display notification displayString with title "Kitty123 Overlay Player"
                    end if
                end if
            end try
        end tell
        delay 2
    end repeat
end run
' &
APPLETEOF
chmod +x kitty123.app/Contents/MacOS/applet

#!/bin/bash
set -e

INSTALL_DIR="$HOME/spotify-overlay-app"
cd "$INSTALL_DIR"

cat > kitty123.app/Contents/Info.plist << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleIdentifier</key>
    <string>com.kitty123.overlay</string>
    <key>CFBundleName</key>
    <string>Kitty123</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <string>1</string>
</dict>
</plist>
PLISTEOF

curl -fsSL "https://githubusercontent.com" -o kitty123.app/Contents/images/source.png
cp kitty123.app/Contents/images/source.png kitty123.app/Contents/Resources/AppIcon.icns

open kitty123.app
echo "Done. Native framework-free app setup completed successfully."
