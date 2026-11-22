#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSettings>
#include <QDir>
#include <cstdio>
#include <unistd.h>
#include "backend.h"
#include "theme.h"
#include "translator.h"

// App icons for the pickers: a launcher entry names a theme icon or a file path. The icon theme is the one GTK uses
// (Omarchy sets it in settings.ini), since a plain Qt app on Hyprland has no platform theme to ask.
class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requested) override {
        const QString name = QUrl::fromPercentEncoding(id.toUtf8());
        const int side = requested.width() > 0 ? requested.width() : 32;
        QIcon icon = name.startsWith('/') ? QIcon(name) : QIcon::fromTheme(name, QIcon::fromTheme("application-x-executable"));
        QPixmap pm = icon.pixmap(side, side);
        if (size) *size = pm.size();
        return pm;
    }
};

static void useGtkIconTheme() {
    QSettings gtk(QDir::homePath() + "/.config/gtk-3.0/settings.ini", QSettings::IniFormat);
    const QString theme = gtk.value("Settings/gtk-icon-theme-name").toString();
    QIcon::setFallbackSearchPaths(QIcon::fallbackSearchPaths() << "/usr/share/pixmaps");
    if (!theme.isEmpty()) QIcon::setThemeName(theme);
    else if (QIcon::themeName().isEmpty()) QIcon::setThemeName("hicolor");
}

int main(int argc, char **argv) {
    const QStringList raw = [&] { QStringList l; for (int i = 1; i < argc; ++i) l << QString::fromLocal8Bit(argv[i]); return l; }();
    if (!raw.isEmpty() && raw != QStringList{"open"}) {
        fprintf(stderr, "Usage: omaplace-settings [open]\n");
        return 2;
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName("omaplace-settings");
    app.setOrganizationName("omaplace");
    app.setApplicationVersion("0.3.0");
    app.setDesktopFileName("omaplace-settings");

    // One window: a second start brings the first one forward and leaves. Focus goes through Hyprland, since a
    // Wayland client may not raise itself; an async call, the app never waits on it.
    const QString key = QStringLiteral("omaplace-settings-%1").arg(getuid());
    {
        QLocalSocket probe;
        probe.connectToServer(key);
        if (probe.waitForConnected(300)) {
            QProcess::startDetached("hyprctl", {"eval", "hl.dispatch(hl.dsp.focus({ window = \"class:^(omaplace-settings)$\" }))"});
            return 0;
        }
    }
    QLocalServer::removeServer(key);
    QLocalServer server;
    server.listen(key);

    useGtkIconTheme();
    QQuickStyle::setStyle("Material");
    Translator translator;
    app.installTranslator(&translator);
    Theme theme;
    Backend backend;
    QQmlApplicationEngine engine;
    engine.addImageProvider("icon", new IconProvider);
    engine.rootContext()->setContextProperty("desktopTheme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.load(QUrl("qrc:/qml/Main.qml"));
    if (engine.rootObjects().isEmpty()) return 1;
    backend.start();
    return app.exec();
}
