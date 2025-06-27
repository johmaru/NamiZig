cmake_minimum_required(VERSION 3.10)

project(ZigWebViewRunner LANGUAGES C)

set(PROJECT_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

set(PROJECT_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}")

set(ZIG_OUTPUT_DIR "${PROJECT_SOURCE_DIR}/zig-out/bin")

set(ZIG_EXECUTABLE_NAME "NamiZig.exe")
set(ZIG_EXECUTABLE_PATH "${ZIG_OUTPUT_DIR}/${ZIG_EXECUTABLE_NAME}")
set(WEBVIEW_DLL_SOURCE "${PROJECT_SOURCE_DIR}/webview/x64/WebView2Loader.dll")
set(WEBVIEW_DLL_DEST "${ZIG_OUTPUT_DIR}/WebView2Loader.dll")

file(GLOB_RECURSE ZIG_SOURCES "${PROJECT_SOURCE_DIR}/src/*.zig")
set(ZIG_BUILD_DEPENDENCIES
    "${PROJECT_SOURCE_DIR}/build.zig"
    ${ZIG_SOURCES}
)

add_custom_command(
    OUTPUT
        ${WEBVIEW_DLL_DEST}
    COMMAND
        ${CMAKE_COMMAND} -E make_directory "${ZIG_OUTPUT_DIR}"
    COMMAND
        ${CMAKE_COMMAND} -E copy_if_different "${WEBVIEW_DLL_SOURCE}" "${WEBVIEW_DLL_DEST}"
    DEPENDS
        ${WEBVIEW_DLL_SOURCE}
    COMMENT "Copying WebView2Loader.dll..."
)

add_custom_command(
    OUTPUT
        ${ZIG_EXECUTABLE_PATH}
    COMMAND
        zig build
    WORKING_DIRECTORY
        ${PROJECT_SOURCE_DIR}
    DEPENDS
        ${ZIG_BUILD_DEPENDENCIES}
    COMMENT "Building Zig executable..."
)

add_custom_target(run
    COMMAND
        ${ZIG_EXECUTABLE_PATH}
    WORKING_DIRECTORY
        ${ZIG_OUTPUT_DIR}
    DEPENDS
        ${ZIG_EXECUTABLE_PATH}
        ${WEBVIEW_DLL_DEST}
    USES_TERMINAL
    COMMENT "Running Zig application..."
)

message(STATUS "---------------------------------------------------------")
message(STATUS "To build and run the application, use the following commands:")
message(STATUS "  1. mkdir build && cd build")
message(STATUS "  2. cmake ..")
message(STATUS "  3. cmake --build . --target run")
message(STATUS "---------------------------------------------------------")