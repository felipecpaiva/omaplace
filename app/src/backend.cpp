#include "backend.h"
#include <QClipboard>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QSaveFile>
#include <QUrl>
#include <unistd.h>

Backend::Backend(const QString &runtimeDir, const QString &shell, QObject *parent)
    : QObject(parent), m_shell(shell.isEmpty() ? QStringLiteral("omarchy-shell") : shell) {
    QString base = runtimeDir;
    if (base.isEmpty()) {
        const QByteArray xdg = qgetenv("XDG_RUNTIME_DIR");
        base = (xdg.isEmpty() ? QStringLiteral("/run/user/%1").arg(getuid()) : QString::fromLocal8Bit(xdg)) + "/omaplace";
    }
    m_runtime = base;
    // A rename into the folder (the service writes atomically) shows as a folder change; the poll covers a folder
    // made after the app started. Both only stat one file.
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Backend::readModelFile);
    m_poll.setInterval(1500);
    connect(&m_poll, &QTimer::timeout, this, &Backend::readModelFile);
}

void Backend::start() {
    if (QDir(m_runtime).exists() && !m_watcher.directories().contains(m_runtime)) m_watcher.addPath(m_runtime);
    if (!m_poll.isActive()) m_poll.start();
    call(QString(), QStringLiteral("appModel"), {QStringLiteral("appModel")});
}

QString Backend::request(const QString &op, const QVariantList &args) {
    const QString id = QStringLiteral("a%1-%2").arg(QCoreApplication::applicationPid()).arg(++m_counter);
    QDir().mkpath(m_runtime);
    QSaveFile file(m_runtime + "/app-" + id + ".json");
    const QJsonObject body{{"contract", Contract}, {"op", op}, {"args", QJsonArray::fromVariantList(args)}};
    if (!file.open(QIODevice::WriteOnly) || file.write(QJsonDocument(body).toJson(QJsonDocument::Compact)) < 0 || !file.commit()) {
        emit replied(id, op, {{"ok", false}, {"code", "failed"}, {"reason", tr("Cannot write the request in %1").arg(m_runtime)}});
        return id;
    }
    call(id, op, {QStringLiteral("app"), id});
    return id;
}

// One IPC call, never through a shell: fixed argv, the request id is ours. The reply file is read and removed here.
void Backend::call(const QString &id, const QString &op, const QStringList &args) {
    auto *p = new QProcess(this);
    auto *timer = new QTimer(p);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, p, [p] { p->kill(); });
    connect(p, &QProcess::finished, this, [this, p, id, op](int code, QProcess::ExitStatus status) {
        p->deleteLater();
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed();
        const QString out = QString::fromUtf8(p->readAllStandardOutput()).trimmed();
        if (status != QProcess::NormalExit || code != 0) {
            setProblem(problemFor(status == QProcess::NormalExit ? code : -1, err));
            if (!id.isEmpty()) {
                QFile::remove(m_runtime + "/app-" + id + ".json");
                emit replied(id, op, {{"ok", false}, {"code", "unreachable"}, {"reason", m_problem}});
            }
            return;
        }
        if (id.isEmpty()) { // appModel: the answer names the service's contract
            const QVariantMap a = QJsonDocument::fromJson(out.toUtf8()).toVariant().toMap();
            if (a.value("contract").toInt() != Contract) { setProblem(problemFor(0, QStringLiteral("contract"))); return; }
            setProblem(QString());
            if (!m_watcher.directories().contains(m_runtime) && QDir(m_runtime).exists()) m_watcher.addPath(m_runtime);
            readModelFile();
            return;
        }
        const QString path = m_runtime + "/app-" + id + "-reply.json";
        QFile f(path);
        QVariantMap reply;
        if (f.open(QIODevice::ReadOnly)) reply = QJsonDocument::fromJson(f.readAll()).toVariant().toMap();
        f.close();
        QFile::remove(path);
        QVariantMap answer = reply.value("answer").toMap();
        if (answer.isEmpty()) answer = QJsonDocument::fromJson(out.toUtf8()).toVariant().toMap();
        if (answer.isEmpty()) answer = {{"ok", false}, {"code", "failed"}, {"reason", tr("No answer from omaplace")}};
        if (answer.value("code").toString() == "contract") setProblem(problemFor(0, QStringLiteral("contract")));
        else setProblem(QString());
        applyModel(reply.value("model").toMap());
        // A slow request (open, restore) answers "pending" with the service's id; its result is asked for once idle.
        if (answer.value("pending").toBool() && !answer.value("req").toString().isEmpty() && op != "result")
            m_waiting.insert(answer.value("req").toString(), op);
        emit replied(id, op, answer);
        finishWaiting();
    });
    timer->start(10000);
    p->start(m_shell, QStringList{QString::fromLatin1(Target)} + args);
}

QString Backend::problemFor(int exitCode, const QString &stderrText) {
    if (stderrText == "contract")
        return tr("This settings app and the omaplace plugin are different versions. Update both: omarchy plugin update, then install the matching omaplace-settings.");
    if (stderrText.contains("Target not found", Qt::CaseInsensitive))
        return tr("The omaplace plugin is not running. Enable it with: omarchy plugin enable io.github.felipecpaiva.omaplace");
    if (stderrText.contains("not found", Qt::CaseInsensitive) || stderrText.contains("No such function", Qt::CaseInsensitive))
        return tr("The omaplace plugin is too old for this settings app. Update it with: omarchy plugin update, then omarchy restart shell.");
    if (exitCode == -1) return tr("omaplace did not answer in time. Try again.");
    if (stderrText.isEmpty() && exitCode == 0) return QString();
    return tr("Cannot reach the Omarchy shell (%1).").arg(stderrText.isEmpty() ? tr("exit %1").arg(exitCode) : stderrText.left(200));
}

bool Backend::applyModel(const QVariantMap &model) {
    if (model.isEmpty()) return false;
    if (model.value("contract").toInt() != Contract) { setProblem(problemFor(0, QStringLiteral("contract"))); return false; }
    const qint64 seq = model.value("seq").toLongLong();
    const qint64 started = model.value("started").toLongLong();
    if (started == m_started && seq <= m_seq) return false; // an older model (a reply raced a push)
    if (started != m_started && started < m_started) return false; // a file left by a service that has gone
    m_started = started;
    m_seq = seq;
    m_model = model;
    emit modelChanged();
    emit connectedChanged();
    if (model.contains("late")) emit replied(QString(), QStringLiteral("late"), model.value("late").toMap());
    finishWaiting();
    return true;
}

void Backend::readModelFile() {
    const QFileInfo info(m_runtime + "/app-model.json");
    if (!info.exists() || info.lastModified() == m_modelTime) return;
    m_modelTime = info.lastModified();
    QFile f(info.filePath());
    if (!f.open(QIODevice::ReadOnly)) return;
    applyModel(QJsonDocument::fromJson(f.readAll()).toVariant().toMap());
}

void Backend::finishWaiting() {
    if (m_waiting.isEmpty() || m_model.value("busy").toBool()) return;
    const auto waiting = m_waiting;
    m_waiting.clear();
    for (auto it = waiting.begin(); it != waiting.end(); ++it) {
        const QString op = it.value();
        const QString rid = request(QStringLiteral("result"), {it.key()});
        // the result's reply is shown as the reply of the op that started it
        auto *link = new QObject(this);
        connect(this, &Backend::replied, link, [this, link, rid, op](const QString &id, const QString &, const QVariantMap &a) {
            if (id != rid) return;
            link->deleteLater();
            emit replied(QStringLiteral("done-") + rid, op, a);
        });
    }
}

void Backend::setProblem(const QString &problem) {
    if (problem == m_problem) return;
    m_problem = problem;
    emit problemChanged();
    emit connectedChanged();
}

// Icons come from the image provider in main.cpp (the icon theme, or a file path from a launcher entry).
QString Backend::iconSource(const QString &name) const {
    if (name.isEmpty()) return QString();
    return QStringLiteral("image://icon/") + QString::fromUtf8(QUrl::toPercentEncoding(name));
}

void Backend::openConfigFolder() const {
    QDesktopServices::openUrl(QUrl::fromLocalFile(QDir::homePath() + "/.config/omaplace"));
}

void Backend::copyText(const QString &text) const {
    if (auto *c = QGuiApplication::clipboard()) c->setText(text);
}
