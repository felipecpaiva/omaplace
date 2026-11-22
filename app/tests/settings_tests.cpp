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

    QQuickItem *byText(QQuickItem *root, const QString &text) {
        for (auto *i : all(root)) if (i->isVisible() && i->property("text").toString() == text && i->property("checkable").isValid()) return i;
        for (auto *i : all(root)) if (i->isVisible() && i->property("text").toString() == text && i->inherits("QQuickAbstractButton")) return i;
        qWarning("no visible button %s", qPrintable(text));
        return nullptr;
    }
    // A ComboBox choice, as a person picks it: the index is set and activated() fires.
    static void choose(QQuickItem *combo, const QString &value) {
        QVERIFY(combo);
        const QVariantList opts = combo->property("model").toList();
        int at = -1;
        for (int i = 0; i < opts.size(); ++i) if (opts.at(i).toMap().value("value").toString() == value) at = i;
        QVERIFY2(at >= 0, qPrintable("no option " + value));
        combo->setProperty("currentIndex", at);
        QMetaObject::invokeMethod(combo, "activated", Q_ARG(int, at));
        QTest::qWait(50);
    }
    // Type into a field and press Enter (editingFinished).
    static void typeIn(QQuickWindow *w, QQuickItem *field, const QString &text) {
        QVERIFY(field);
        click(w, field);
        QTest::keyClick(w, Qt::Key_A, Qt::ControlModifier);
        for (const QChar c : text) QTest::keyClick(w, c.toLatin1());
        QTest::keyClick(w, Qt::Key_Return);
        QTest::qWait(50);
    }
    struct Window {
        Theme theme;
        Backend backend;
        QQmlApplicationEngine engine;
        QQuickWindow *w = nullptr;
        Window(const QString &rt, const QString &shell) : backend(rt, shell) {
            engine.addImageProvider("icon", new IconProvider);
            engine.rootContext()->setContextProperty("desktopTheme", &theme);
            engine.rootContext()->setContextProperty("backend", &backend);
            engine.load(QUrl("qrc:/qml/Main.qml"));
            w = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
            if (w) w->show();
            backend.start();
        }
    };

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

    // Every control not covered by pages(): each sends one request with the right arguments.
    void everyControl() {
        reset();
        g_warnings.clear();
        g_previous = qInstallMessageHandler(collect);
        Window win(m_rt, m_shell);
        auto *w = win.w;
        QVERIFY(w);
        QTRY_VERIFY_WITH_TIMEOUT(win.backend.connected(), 5000);
        QTest::qWait(300);
        auto *c = w->contentItem();

        // Desktops: desktop 2 (plan, 2 columns): layout, an app in zone 2, open at login
        click(w, all(c, "tile-2").at(0));
        choose(find(c, "layoutPicker"), "columns:3");
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",2,true,"layout","columns:3","floating"])"), 5000);
        click(w, find(c, "zoneApp-2"));
        for (const QChar ch : QString("calc")) QTest::keyClick(w, ch.toLatin1());
        QTest::keyClick(w, Qt::Key_Return);
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",2,true,"app",{"id":"org.example.Calc","pos":2},"floating"])"), 5000);
        QTest::qWait(400); // the picker's list closes with a short animation
        click(w, find(c, "openAtLogin"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",2,true,"login",false,"floating"])"), 5000);
        click(w, byText(c, "Clear"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",2,true,"clear",1,"floating"])"), 5000);
        click(w, byText(c, "More"));
        typeIn(w, find(c, "folderField"), "~/example");
        QTRY_VERIFY_WITH_TIMEOUT(sent("setWindow", R"(["desk-2",0,"org.example.Editor","folder","~/example"])"), 5000);
        click(w, byText(c, "Edit in omagnet"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("openOmagnet"), 5000);
        // the built-in zone editor shows when omagnet is not there: draw, split, save
        QVariantMap m = win.backend.model();
        QVariantMap desks = m.value("desks").toMap();
        desks.insert("omagnet", QVariantMap{{"loaded", false}, {"layouts", QVariantList{}}});
        m.insert("desks", desks);
        m.insert("seq", 100000);
        QVERIFY(win.backend.applyModel(m));
        QTest::qWait(200);
        QVERIFY2(!find(c, "layoutPicker") || byText(c, "Edit in omagnet") == nullptr, "Edit in omagnet hidden without omagnet");
        click(w, find(c, "drawZones"));
        click(w, byText(c, "Split vertical"));  // nothing selected: says so, changes nothing
        grab(w, "zone-editor");
        click(w, byText(c, "Save"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",2,true,"layout","0 0 0.5 1; 0.5 0 0.5 1","floating"])"), 5000);
        // a desktop with no plan: picking a layout makes one; "No plan" on a plan asks first
        click(w, all(c, "tile-3").at(0));
        choose(find(c, "layoutPicker"), "tiled");
        QTRY_VERIFY_WITH_TIMEOUT(sent("editPlan", R"(["Example Corp EX27",3,true,"layout","tiled","tiled"])"), 5000);

        // Apps: each rule control, app memory, ignored apps
        click(w, find(c, "nav1"));
        click(w, find(c, "ruleOn-editor"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setRule", R"(["editor","enabled",false])"), 5000);
        click(w, find(c, "ruleFollow-editor"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setRule", R"(["editor","follow",true])"), 5000);
        click(w, find(c, "ruleSpot-editor"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setRule", R"(["editor","keep_rect",false])"), 5000);
        QVERIFY2(!find(c, "ruleSpot-chat") , "Same spot only for a rule with a rect");
        choose(find(c, "ruleMonitor-editor"), "laptop");
        QTRY_VERIFY_WITH_TIMEOUT(sent("setRule", R"(["editor","monitor","laptop"])"), 5000);
        auto *slot = find(c, "ruleSlot-editor");
        QMetaObject::invokeMethod(slot, "increase");
        QMetaObject::invokeMethod(slot, "valueModified");
        QTRY_VERIFY_WITH_TIMEOUT(sent("setRule", R"(["editor","slot",4])"), 5000);
        click(w, byText(c, "Where you left it"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["app_memory","last_place"])"), 5000);
        click(w, byText(c, "Use the focused monitor"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["missing_monitor_rule","focused"])"), 5000);
        typeIn(w, find(c, "ignoreField"), "steam, mpv");
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["ignore","steam, mpv"])"), 5000);
        click(w, byText(c, "Remove"));
        auto *confirm = win.engine.rootObjects().first()->findChild<QObject *>("confirm");
        QTRY_VERIFY_WITH_TIMEOUT(confirm->property("visible").toBool(), 3000);
        QMetaObject::invokeMethod(confirm, "reject");
        QTRY_VERIFY_WITH_TIMEOUT(!confirm->property("visible").toBool(), 3000);
        QVERIFY2(!sent("removeRule"), "Cancel removes nothing");

        // Scenes: rename, windows, choose a folder for the unknown project
        click(w, find(c, "nav2"));
        typeIn(w, find(c, "sceneName-work"), "work-2");
        QTRY_VERIFY_WITH_TIMEOUT(sent("rename", R"(["work","work-2"])"), 5000);
        click(w, find(c, "sceneWindows-work"));
        click(w, find(c, "chooseFolder"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("pickFolder", R"(["work",0,"org.example.Editor"])"), 5000);
        click(w, byText(c, "Open new ones"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["existing_default","new"])"), 5000);
        grab(w, "page-scenes-windows");

        // Restore: restore at login, the snapshot switch, an older session (this login's own cannot be restored)
        click(w, find(c, "nav3"));
        click(w, byText(c, "Automatic"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["restore_at_login","auto"])"), 5000);
        click(w, byText(c, "Keep a session snapshot"));
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["session","off"])"), 5000);
        QList<QQuickItem *> restores;
        for (auto *i : all(c)) if (i->isVisible() && i->property("text").toString() == "Restore" && i->inherits("QQuickAbstractButton") && !i->objectName().startsWith("nav")) restores << i;
        QCOMPARE(restores.size(), 2);
        QCOMPARE(restores.at(0)->isEnabled(), false);
        click(w, restores.at(1));
        QTRY_VERIFY_WITH_TIMEOUT(sent("restore", R"(["abc_1699900000_1"])"), 5000);

        // General: a timing
        click(w, find(c, "nav4"));
        click(w, find(c, "advancedButton"));
        QQuickItem *spin = nullptr;
        for (auto *i : all(c)) if (i->isVisible() && i->inherits("QQuickSpinBox")) { spin = i; break; }
        QVERIFY(spin);
        QMetaObject::invokeMethod(spin, "increase");
        QMetaObject::invokeMethod(spin, "valueModified");
        QTRY_VERIFY_WITH_TIMEOUT(sent("setSetting", R"(["expiry_seconds",21])"), 5000);

        // Keyboard: Tab reaches the pages' controls; ? opens the shortcuts
        click(w, find(c, "nav0"));  // out of the number field, which takes typed keys itself
        QTest::keyClick(w, Qt::Key_Question, Qt::ShiftModifier);
        auto *help = win.engine.rootObjects().first()->findChild<QObject *>("help");
        QTRY_VERIFY_WITH_TIMEOUT(help->property("visible").toBool(), 3000);
        grab(w, "help");
        QMetaObject::invokeMethod(help, "accept");

        qInstallMessageHandler(g_previous);
        const QStringList qmlWarnings = g_warnings.filter(QRegularExpression("qml|QML|\\.js:"));
        QVERIFY2(qmlWarnings.isEmpty(), qPrintable(qmlWarnings.join("\n")));
    }

    // The window says why it cannot work, never shows an empty page.
    void problemBanner() {
        reset("missing");
        Window win(m_rt, m_shell);
        QVERIFY(win.w);
        QTRY_VERIFY_WITH_TIMEOUT(!win.backend.problem().isEmpty(), 5000);
        QTest::qWait(200);
        auto *banner = find(win.w->contentItem(), "problem");
        QVERIFY(banner);
        grab(win.w, "problem");
        reset();
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
