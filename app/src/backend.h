#pragma once
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

// The app's link to the omaplace service (design 17, D37, D38). The service is the only writer and keeps all logic:
// each action is one request file in the runtime folder plus one IPC call, and the reply carries the next model. The
// service also rewrites app-model.json when something changes (live desktops read, a scene opened), watched here.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap model READ model NOTIFY modelChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY problemChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
public:
    static constexpr int Contract = 1;
    static constexpr const char *Target = "io.github.felipecpaiva.omaplace";

    // runtimeDir and shell are for tests; the defaults are $XDG_RUNTIME_DIR/omaplace and omarchy-shell.
    explicit Backend(const QString &runtimeDir = {}, const QString &shell = {}, QObject *parent = nullptr);

    QVariantMap model() const { return m_model; }
    QString problem() const { return m_problem; }
    bool connected() const { return m_problem.isEmpty() && !m_model.isEmpty(); }
    QString runtimeDir() const { return m_runtime; }

    // Ask for the model (IPC appModel); the service starts its live desktops read and pushes the model again after.
    Q_INVOKABLE void start();
    // One action. Returns the request id; replied(id, op, answer) follows. args are JSON scalars.
    Q_INVOKABLE QString request(const QString &op, const QVariantList &args = {});
    Q_INVOKABLE QString iconSource(const QString &name) const;
    Q_INVOKABLE void openConfigFolder() const;
    Q_INVOKABLE void copyText(const QString &text) const;

    // Plain helpers, public for tests.
    static QString problemFor(int exitCode, const QString &stderrText);
    bool applyModel(const QVariantMap &model);

signals:
    void modelChanged();
    void problemChanged();
    void connectedChanged();
    void replied(const QString &id, const QString &op, const QVariantMap &answer);

private:
    void call(const QString &id, const QString &op, const QStringList &args);
    void readModelFile();
    void setProblem(const QString &problem);
    void finishWaiting();

    QString m_runtime, m_shell, m_problem;
    QVariantMap m_model;
    qint64 m_seq = -1;
    int m_counter = 0;
    QFileSystemWatcher m_watcher;
    QTimer m_poll;
    QDateTime m_modelTime;
    QHash<QString, QString> m_waiting; // a slow request's service id -> the op that started it
};
