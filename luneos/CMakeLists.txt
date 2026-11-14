cmake_minimum_required(VERSION 3.21)
project(musicfox-touch-luneos VERSION 0.5.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick Network Multimedia DBus)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(SHARED_APP "${CMAKE_CURRENT_SOURCE_DIR}/../app")
set(GENERATED_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(QML_NAMES main.qml FrostedBackground.qml GlassPanel.qml VinylDisc.qml BaguaDial.qml
    KtvLyrics.qml SpectrumBars.qml kitty-dark.png trigram-recolored2.png taiji-disc.png)
set(QML_RESOURCES)
foreach(name IN LISTS QML_NAMES)
    list(APPEND QML_RESOURCES "${GENERATED_DIRECTORY}/qml/${name}")
endforeach()
file(GLOB SHARED_QML CONFIGURE_DEPENDS "${SHARED_APP}/qml/*.qml" "${SHARED_APP}/qml/*.png")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${SHARED_QML} "${SHARED_APP}/src/pulselevels.cpp" "${SHARED_APP}/src/covercache.cpp"
    "${SHARED_APP}/src/neteaseapi.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/generate-sources.py")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/generate-sources.py"
    "${SHARED_APP}" "${GENERATED_DIRECTORY}" COMMAND_ERROR_IS_FATAL ANY)

add_library(musicfox-luneos-core STATIC
    src/mpvcontroller.cpp src/mpvcontroller.h
    "${GENERATED_DIRECTORY}/neteaseapi.cpp" "${SHARED_APP}/src/neteaseapi.h"
    "${SHARED_APP}/src/playqueue.cpp" "${SHARED_APP}/src/playqueue.h"
    "${SHARED_APP}/src/lyricsync.cpp" "${SHARED_APP}/src/lyricsync.h"
    "${GENERATED_DIRECTORY}/covercache.cpp" "${SHARED_APP}/src/covercache.h"
    "${GENERATED_DIRECTORY}/pulselevels.cpp" "${SHARED_APP}/src/pulselevels.h")
target_include_directories(musicfox-luneos-core PUBLIC src "${SHARED_APP}/src")
target_link_libraries(musicfox-luneos-core PUBLIC Qt6::Core Qt6::Network Qt6::Multimedia)

qt_add_executable(musicfox-touch src/main.cpp)
target_link_libraries(musicfox-touch PRIVATE musicfox-luneos-core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::DBus)
target_link_options(musicfox-touch PRIVATE "LINKER:--as-needed")
qt_add_resources(musicfox-touch musicfox-qml PREFIX "/" BASE "${GENERATED_DIRECTORY}" FILES ${QML_RESOURCES})
set_target_properties(musicfox-touch PROPERTIES INSTALL_RPATH "")

set(MUSICFOX_DAEMON "${CMAKE_CURRENT_SOURCE_DIR}/../daemon/musicfox-daemon" CACHE FILEPATH "aarch64 MusicFox Go daemon")
if(NOT EXISTS "${MUSICFOX_DAEMON}")
    message(FATAL_ERROR "Build the Go daemon first or pass -DMUSICFOX_DAEMON=/path/to/musicfox-daemon")
endif()
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/libexec")
configure_file("${MUSICFOX_DAEMON}" "${CMAKE_BINARY_DIR}/libexec/musicfox-daemon" COPYONLY)

install(TARGETS musicfox-touch RUNTIME DESTINATION bin)
install(PROGRAMS "${MUSICFOX_DAEMON}" DESTINATION libexec)
install(PROGRAMS packaging/musicfox-touch DESTINATION .)
install(PROGRAMS packaging/luna-call DESTINATION .)
install(FILES packaging/appinfo.json DESTINATION .)
install(FILES "${SHARED_APP}/qml/kitty-dark.png" DESTINATION . RENAME icon.png)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(musicfox-core-tests tests/core-tests.cpp)
    target_link_libraries(musicfox-core-tests PRIVATE musicfox-luneos-core Qt6::Test)
    target_link_options(musicfox-core-tests PRIVATE "LINKER:--as-needed")
    add_test(NAME core COMMAND musicfox-core-tests)
    add_test(NAME qml-startup COMMAND musicfox-touch --smoke-test)
    set_tests_properties(core qml-startup PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()
