cmake_minimum_required(VERSION 3.20)
project(LevelDevilLauncher CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
    add_compile_options(/W4 /utf-8 /permissive- /EHsc)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
    # Static CRT so the launcher runs on machines without VC++ redistributable.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_executable(LevelDevilLauncher
    src/launcher.cpp
)

target_link_libraries(LevelDevilLauncher PRIVATE
    winhttp
    shlwapi
    user32
    advapi32
)

set_target_properties(LevelDevilLauncher PROPERTIES
    OUTPUT_NAME "LevelDevilLauncher"
)

install(TARGETS LevelDevilLauncher RUNTIME DESTINATION .)
