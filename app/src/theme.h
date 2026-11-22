// Copied from omadials-settings (MIT, same author), the Omarchy app recipe: follows the theme and the language live.
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(int radius READ radius NOTIFY changed)
    // Every "name = \"#rrggbb\"" pair of the current Omarchy theme (colors.toml), so the app paints in that theme.
    Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr, const QString &hyprctl = {});
    ~Theme() override;

    QString accent() const { return m_accent; }
    QString accentForeground() const;
    int radius() const { return m_radius; }
    QVariantMap colors() const { return m_colors; }
    static QVariantMap readColors(const QString &path);

    static QString readAccent(const QString &path);

signals:
    void changed();

private:
    void reload();
    void refreshRounding();

    QString m_directory;
    QString m_accent = "#FFD60A";
    QVariantMap m_colors;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QString m_hyprctl;
    int m_radius = 0;
    QProcess m_roundingProcess;
    QTimer m_roundingPoll, m_roundingTimeout;
};
