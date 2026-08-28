QT += quick qml network multimedia dbus
TARGET = harbour-musicfox
CONFIG += c++14 link_pkgconfig
QMAKE_LFLAGS += -pie -rdynamic
PKGCONFIG += Qt5Gui sailfishsilica
LIBS += -l:libsailfishapp.so.1

SOURCES += \
    src/main.cpp \
    src/neteaseapi.cpp \
    src/mpvcontroller.cpp \
    src/playqueue.cpp \
    src/lyricsync.cpp \
    src/covercache.cpp

HEADERS += \
    src/neteaseapi.h \
    src/mpvcontroller.h \
    src/playqueue.h \
    src/lyricsync.h \
    src/covercache.h

RESOURCES += qml.qrc
