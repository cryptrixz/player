const { app, BrowserWindow, screen } = require('electron');
const path = require('path');

function createOverlayWindow() {
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;

    const win = new BrowserWindow({
        width: 480,
        height: 110,
        x: Math.floor((width - 480) / 2),
        y: height - 130,
        frame: false,
        transparent: true,
        alwaysOnTop: true,
        resizable: false,
        hasShadow: false,
        skipTaskbar: true,
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true
        }
    });

    win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    win.setAlwaysOnTop(true, 'screen-saver', 1);
    win.setIgnoreMouseEvents(true, { forward: true });

    win.loadFile(path.join(__dirname, 'overlay.html'));
}

app.whenReady().then(() => {
    createOverlayWindow();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createOverlayWindow();
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});
