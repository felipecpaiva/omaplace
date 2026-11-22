QT += core gui qml quick quickcontrols2
CONFIG += c++17 release
TARGET = omaplace-settings
TEMPLATE = app
HEADERS += src/backend.h src/theme.h src/translator.h
SOURCES += src/main.cpp src/backend.cpp src/theme.cpp src/translator.cpp
!system(python3 $$PWD/prepare.py): error(Resource preparation failed)
RESOURCES += resources.qrc
# a change to the plugin's shared js/ runs qmake again on the next make
QMAKE_INTERNAL_INCLUDED_FILES += $$files($$PWD/../js/*.js) $$files($$PWD/qml/*.qml) $$files($$PWD/qml/*.js)
