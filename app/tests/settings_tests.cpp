// Offscreen tests of the settings app: the Backend against a fake omarchy-shell (fake-shell.sh) and the real QML pages
// driven with mouse and key events. Made-up data only (fixture-model.json, written by make_fixture.mjs).
#include <QtTest>
#include <QQuickStyle>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include "backend.h"
#include "theme.h"

static QStringList g_warnings;
static QtMessageHandler g_previous = nullptr;
static void collect(QtMsgType type, const QMessageLogContext &ctx, const QString &msg) {
    if (type == QtWarningMsg || type == QtCriticalMsg) g_warnings << msg;
    if (g_previous) g_previous(type, ctx, msg);
}

class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &, QSize *size, const QSize &) override {
        QPixmap pm(16, 16); pm.fill(Qt::gray); if (size) *size = pm.size(); return pm;
    }
};

class SettingsTests : public QObject {
    Q_OBJECT
    QTemporaryDir m_dir;
    QString m_shell, m_rt;

    QStringList requests() {
        QFile f(m_rt + "/requests.log");
        if (!f.open(QIODevice::ReadOnly)) return {};
        return QString::fromUtf8(f.readAll()).split('\n', Qt::SkipEmptyParts);
    }
    void reset(const QString &mode = {}) {
        QDir(m_rt).removeRecursively();
        QDir().mkpath(m_rt);
        qputenv("FAKE_MODE", mode.toUtf8());
    }
    // Items made by a Repeater have no QObject parent, so walk the visual tree (popups live in the overlay, also in it).
    static void walk(QQuickItem *item, QList<QQuickItem *> &out) {
        if (!item) return;
        out << item;
        for (auto *c : item->childItems()) walk(c, out);
    }
    static QList<QQuickItem *> all(QQuickItem *root, const QString &name = {}) {
        QList<QQuickItem *> list, out;
        walk(root, list);
        for (auto *i : list) if (name.isEmpty() || i->objectName() == name) out << i;
        return out;
    }
    static QQuickItem *find(QQuickItem *root, const QString &name) {
        for (auto *i : all(root, name)) if (i->isVisible()) return i;
        qWarning("no visible item %s", qPrintable(name));
        return nullptr;
    }
    bool sent(const QString &op, const QString &argsJson = {}) {
        for (const QString &line : requests()) {
            const QJsonObject o = QJsonDocument::fromJson(line.toUtf8()).object();
            if (o.value("op").toString() != op) continue;
            if (argsJson.isEmpty() || QJsonDocument(o.value("args").toArray()).toJson(QJsonDocument::Compact) == argsJson) return true;
        }
        return false;
    }
    // Scroll the page so the item is on screen, as a person would before clicking it.
    static void reveal(QQuickWindow *w, QQuickItem *item) {
        for (QQuickItem *p = item->parentItem(); p; p = p->parentItem()) {
            if (!p->property("contentY").isValid() || !p->property("contentHeight").isValid()) continue;
            const qreal y = item->mapToItem(p->property("contentItem").value<QQuickItem *>(), QPointF(0, 0)).y();
            const qreal top = p->property("contentY").toReal(), h = p->height();
            if (y < top || y + item->height() > top + h) p->setProperty("contentY", qMax(0.0, y - h / 3));
            QTest::qWait(50);
            break;
        }
        Q_UNUSED(w);
    }
    static void click(QQuickWindow *w, QQuickItem *item) {
        QVERIFY(item);
        QVERIFY2(item->isVisible(), "item hidden");
        reveal(w, item);
        const QPointF p = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
        QTest::mouseClick(w, Qt::LeftButton, {}, p.toPoint());
        QTest::qWait(50);
    }
    void grab(QQuickWindow *w, const QString &name) {
        QTest::qWait(200);
        w->grabWindow().save(QStringLiteral(SRCDIR) + "/" + name + ".png");
    }

private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        m_rt = m_dir.path() + "/rt";
        m_shell = QStringLiteral(SRCDIR) + "/fake-shell.sh";
        qputenv("FAKE_RT", m_rt.toUtf8());
        qputenv("FAKE_FIXTURE", (QStringLiteral(SRCDIR) + "/fixture-model.json").toUtf8());
        QVERIFY2(QFile::exists(QStringLiteral(SRCDIR) + "/fixture-model.json"), "run make_fixture.mjs first");
    }

    void startReadsTheModel() {
        reset();
        Backend b(m_rt, m_shell);
        QSignalSpy changed(&b, &Backend::modelChanged);
        b.start();
        QTRY_VERIFY_WITH_TIMEOUT(b.connected(), 5000);
        QCOMPARE(b.model().value("contract").toInt(), 1);
        QCOMPARE(b.model().value("apps").toList().size(), 5);
        QVERIFY(changed.count() >= 1);
    }

    void requestRoundTrip() {
        reset();
        Backend b(m_rt, m_shell);
        b.start();
        QTRY_VERIFY_WITH_TIMEOUT(b.connected(), 5000);
        QSignalSpy replied(&b, &Backend::replied);
        const QString id = b.request("setSetting", {"app_memory", "off"});
        QTRY_COMPARE_WITH_TIMEOUT(replied.count(), 1, 5000);
        QCOMPARE(replied.at(0).at(0).toString(), id);
        QCOMPARE(replied.at(0).at(1).toString(), QString("setSetting"));
        QCOMPARE(replied.at(0).at(2).toMap().value("ok").toBool(), true);
        QCOMPARE(requests().size(), 1);
        QVERIFY(requests().at(0).contains("\"args\":[\"app_memory\",\"off\"]"));
        QVERIFY2(!QFile::exists(m_rt + "/app-" + id + ".json"), "the request file is gone");
        QVERIFY2(!QFile::exists(m_rt + "/app-" + id + "-reply.json"), "the reply file is removed after reading");
    }

    void problemsAreSaidInWords() {
        QCOMPARE(Backend::problemFor(1, "Target not found."), Backend::problemFor(1, "Target not found."));
        QVERIFY(Backend::problemFor(1, "Target not found.").contains("not running"));
        QVERIFY(Backend::problemFor(1, "Function not found.").contains("too old"));
        QVERIFY(Backend::problemFor(0, "contract").contains("different versions"));
        QVERIFY(Backend::problemFor(-1, "").contains("in time"));
        QVERIFY(Backend::problemFor(0, "").isEmpty());
        for (const QString mode : {"missing", "old", "contract"}) {
            reset(mode);
            Backend b(m_rt, m_shell);
            b.start();
            QTRY_VERIFY_WITH_TIMEOUT(!b.problem().isEmpty(), 5000);
            QVERIFY2(!b.connected(), qPrintable(mode));
        }
        reset();
    }

    void anOlderModelIsIgnored() {
        Backend b(m_rt, m_shell);
        QVERIFY(b.applyModel({{"contract", 1}, {"seq", 5}, {"busy", false}}));
        QVERIFY(!b.applyModel({{"contract", 1}, {"seq", 4}}));
        QVERIFY(!b.applyModel({{"contract", 2}, {"seq", 9}}));
        QCOMPARE(b.model().value("seq").toInt(), 5);
    }

    void aSlowRequestGetsItsResult() {
        reset("pending");
        Backend b(m_rt, m_shell);
        b.start();
        QTRY_VERIFY_WITH_TIMEOUT(b.connected(), 5000);
        QSignalSpy replied(&b, &Backend::replied);
        b.request("open", {"desk-2"});
        // first the pending answer, then, once the pushed model is idle, the result shown as the open's reply
        QTRY_VERIFY_WITH_TIMEOUT(std::any_of(replied.begin(), replied.end(), [](const QList<QVariant> &r) {
            return r.at(0).toString().startsWith("done-") && r.at(1).toString() == "open" && r.at(2).toMap().value("state") == "done";
        }), 8000);
        QVERIFY(sent("result", R"(["q1-1"])"));
        reset();
    }

    // The real window: every page loads without a QML warning and its main controls send the right request.
    void pages() {
        reset();
        g_warnings.clear();
        g_previous = qInstallMessageHandler(collect);
        Theme theme;
        Backend backend(m_rt, m_shell);
        QQmlApplicationEngine engine;
        engine.addImageProvider("icon", new IconProvider);
        engine.rootContext()->setContextProperty("desktopTheme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(w);
        w->show();
        backend.start();
        QTRY_VERIFY_WITH_TIMEOUT(backend.connected(), 5000);
        QTest::qWait(300);

        // Desktops: the map, the first tile selected, a tile on the laptop panel shows omagnet's layout first
        grab(w, "page-desktops");
        auto tiles = all(w->contentItem(), "tile-1");
        QCOMPARE(tiles.size(), 2);
        click(w, tiles.at(1));
        auto *picker = find(w->contentItem(), "layoutPicker");
        QVERIFY(picker);
        QCOMPARE(picker->property("displayText").toString(), QString("No plan"));
        QVariantList opts = picker->property("model").toList();
        QCOMPARE(opts.at(1).toMap().value("label").toString(), QString("2 columns (omagnet, this desktop)"));
        grab(w, "page-desktops-laptop");
        // desktop 2 of the big monitor has a plan: Open all sends open with its scene name
        click(w, all(w->contentItem(), "tile-2").at(0));
        click(w, find(w->contentItem(), "openAll"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("open", R"(["desk-2"])"), 5000);
        grab(w, "page-desktops-plan");
        // the editor fits in the window: nothing of it is cut off on the right
        {
            auto *ed = find(w->contentItem(), "desktopEditor");
            const QRectF r = ed->mapRectToScene(QRectF(0, 0, ed->width(), ed->height()));
            QList<QQuickItem *> inside;
            walk(ed, inside);
            for (auto *c : inside) {
                if (!c->isVisible() || c->width() == 0 || qobject_cast<QQuickItem *>(c)->property("text").toString().isEmpty()) continue;
                const QRectF cr = c->mapRectToScene(QRectF(0, 0, c->width(), c->height()));
                QVERIFY2(cr.right() <= r.right() + 1, qPrintable(QString("'%1' sticks out of the editor").arg(c->property("text").toString())));
            }
            QVERIFY2(r.right() <= w->width() - 16 + 1, qPrintable(QString("editor right edge %1 of %2").arg(r.right()).arg(w->width())));
        }

        // Apps: pick an app in the searchable picker (type, Enter), then Add sends ruleNew with its id
        click(w, find(w->contentItem(), "nav1"));
        grab(w, "page-apps");
        click(w, find(w->contentItem(), "newRuleApp"));
        for (const QChar c : QString("calc")) QTest::keyClick(w, c.toLatin1());
        QTest::keyClick(w, Qt::Key_Return);
        QTest::qWait(100);
        click(w, find(w->contentItem(), "newRuleAdd"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("ruleNew", R"(["org.example.Calc","",1])"), 5000);

        // Scenes: Delete asks first; Yes sends removeScene
        click(w, find(w->contentItem(), "nav2"));
        grab(w, "page-scenes");
        QQuickItem *del = nullptr;
        for (auto *b : all(w->contentItem()))
            if (b->property("text").toString() == "Delete" && b->isVisible()) { del = b; break; }
        click(w, del);
        auto *confirm = engine.rootObjects().first()->findChild<QObject *>("confirm");
        QTRY_VERIFY_WITH_TIMEOUT(confirm->property("visible").toBool(), 3000);
        grab(w, "page-scenes-confirm");
        QMetaObject::invokeMethod(confirm, "accept");
        QTRY_VERIFY_WITH_TIMEOUT(!confirm->property("visible").toBool(), 3000);
        QTRY_VERIFY_WITH_TIMEOUT(sent("removeScene", R"(["desk-2"])"), 5000);

        // Restore: the big button restores the last session; the login choice is the fixture's "ask"
        click(w, find(w->contentItem(), "nav3"));
        grab(w, "page-restore");
        click(w, find(w->contentItem(), "restoreLast"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("restore", R"([""])"), 5000);

        // General: the menu button and the timings
        click(w, find(w->contentItem(), "nav4"));
        click(w, find(w->contentItem(), "advancedButton"));
        grab(w, "page-general");
        click(w, find(w->contentItem(), "menuButton"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("menuAdd"), 5000);

        // Keyboard: Ctrl+1 goes back to Desktops
        QTest::keyClick(w, Qt::Key_1, Qt::ControlModifier);
        QTRY_COMPARE(engine.rootObjects().first()->property("page").toInt(), 0);

        qInstallMessageHandler(g_previous);
        const QStringList qmlWarnings = g_warnings.filter(QRegularExpression("qml|QML|\\.js:"));
        QVERIFY2(qmlWarnings.isEmpty(), qPrintable(qmlWarnings.join("\n")));
    }
};

int main(int argc, char **argv) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Material");
    SettingsTests t;
    return QTest::qExec(&t, argc, argv);
}

#include "settings_tests.moc"
