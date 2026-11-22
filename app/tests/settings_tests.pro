QT += core gui qml quick quickcontrols2 testlib
CONFIG += c++17 testcase no_testcase_installs
TARGET = settings-tests
TEMPLATE = app
INCLUDEPATH += ../src
HEADERS += ../src/backend.h ../src/theme.h
SOURCES += settings_tests.cpp ../src/backend.cpp ../src/theme.cpp
RESOURCES += ../resources.qrc
DEFINES += SRCDIR=\\\"$$PWD\\\"
