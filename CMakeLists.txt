# Shadowrun (Sega Genesis) - native static recompilation.
#
# Layout follows the other game projects: the engine is the segagenesisrecomp
# submodule, this repository owns game/ (configuration + adapter) and the
# generated C is a build product, never a repository input.
#
#   cmake -S . -B build -G "MinGW Makefiles"
#   cmake --build build -j
#
# The ROM must sit at game/shadowrun.bin (git-ignored): the generated sources
# are produced from it at build time, so a stale or different image cannot be
# compiled by accident.
cmake_minimum_required(VERSION 3.19)
project(ShadowrunRecomp VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(SHADOWRUN_BUILD_VERSION "${PROJECT_VERSION}" CACHE STRING "Build version")
set(ROM_NAME "shadowrun.bin")
set(PREFIX "shadowrun")

# --- engine checkout -------------------------------------------------------
set(GENESIS_RECOMP_ROOT "" CACHE PATH
    "Optional shared Genesis framework checkout (defaults to the submodule)")
if(GENESIS_RECOMP_ROOT)
    set(RECOMP_ROOT "${GENESIS_RECOMP_ROOT}")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/engine-local")
    set(RECOMP_ROOT "${CMAKE_SOURCE_DIR}/engine-local")
else()
    set(RECOMP_ROOT "${CMAKE_SOURCE_DIR}/segagenesisrecomp")
endif()
set(RUNNER_ROOT "${RECOMP_ROOT}/runner")
if(NOT EXISTS "${RUNNER_ROOT}/main.c")
    message(FATAL_ERROR
        "segagenesisrecomp not found at ${RECOMP_ROOT}. Initialise the submodule:\n"
        "  git submodule update --init --recursive")
endif()

# --- SDL2 (bundled with the engine on Windows) -----------------------------
set(SDL2_BUNDLED "${RUNNER_ROOT}/external/SDL2/SDL2-2.28.5")
if(WIN32 AND EXISTS "${SDL2_BUNDLED}/cmake")
    find_package(SDL2 REQUIRED CONFIG PATHS "${SDL2_BUNDLED}/cmake" NO_DEFAULT_PATH)
else()
    find_package(SDL2 REQUIRED)
endif()

# The runner includes <SDL2/SDL.h>; some SDL2 packages point at .../include/SDL2.
set(SDL2_PARENT_INCLUDE_DIRS "")
foreach(_inc IN LISTS SDL2_INCLUDE_DIRS)
    get_filename_component(_inc_name "${_inc}" NAME)
    if(_inc_name STREQUAL "SDL2")
        get_filename_component(_inc_parent "${_inc}" DIRECTORY)
        list(APPEND SDL2_PARENT_INCLUDE_DIRS "${_inc_parent}")
    endif()
endforeach()

# --- audio (YM2612 is C++ on top of ymfm) ----------------------------------
set(FM_SOURCES
    "${RUNNER_ROOT}/audio/ym2612_ymfm.cpp"
    "${RUNNER_ROOT}/external/ymfm/src/ymfm_opn.cpp"
    "${RUNNER_ROOT}/external/ymfm/src/ymfm_ssg.cpp"
    "${RUNNER_ROOT}/external/ymfm/src/ymfm_adpcm.cpp"
    "${RUNNER_ROOT}/external/ymfm/src/ymfm_pcm.cpp")

option(SHADOWRUN_ENABLE_TRACE "TCP debug server + observability rings" OFF)
if(SHADOWRUN_ENABLE_TRACE)
    set(GEN_TRACE_SOURCES "${RUNNER_ROOT}/cmd_server.c" "${RUNNER_ROOT}/frame_snapshots.c")
    add_compile_definitions(GEN_ENABLE_TRACE=1)
else()
    set(GEN_TRACE_SOURCES "${RUNNER_ROOT}/cmd_server_stub.c")
endif()

set(RUNNER_SOURCES
    "${RUNNER_ROOT}/main.c"
    "${RUNNER_ROOT}/audio.c"
    ${GEN_TRACE_SOURCES}
    "${RUNNER_ROOT}/glue.c"
    "${RUNNER_ROOT}/fiber_compat.c"
    "${RUNNER_ROOT}/crash_report.c"
    "${RUNNER_ROOT}/input_script.c"
    "${RUNNER_ROOT}/reverse_debug.c"
    "${RUNNER_ROOT}/gamepad.c"
    "${RUNNER_ROOT}/input_map.c"
    "${RUNNER_ROOT}/app_config.c"
    "${RUNNER_ROOT}/chip_trace.c"
    "${RUNNER_ROOT}/audio/event_queue.c"
    ${FM_SOURCES}
    "${RUNNER_ROOT}/audio/sn76489.c"
    "${RUNNER_ROOT}/audio/mixer.c"
    "${RUNNER_ROOT}/audio/observability.c"
    "${RUNNER_ROOT}/audio/audio_shadow.c"
    "${RUNNER_ROOT}/audio/fm_shadow.cpp"
    "${RUNNER_ROOT}/video/color_lut.c"
    "${RUNNER_ROOT}/video/genesis_vdp.c"
    "${RUNNER_ROOT}/video/genesis_bus.c"
    "${RUNNER_ROOT}/video/genesis_machine.c"
    "${RUNNER_ROOT}/external/superzazu/z80.c"
    "${RUNNER_ROOT}/m68k_interp.c"
    "${RECOMP_ROOT}/recompiler/src/m68k_decoder.c"
    "${RECOMP_ROOT}/recompiler/src/rom_parser.c")

include("${RECOMP_ROOT}/cmake/GenesisRecompGenerated.cmake")
genesisrecomp_add_generated_sources(
    GENERATED_SOURCES "${PREFIX}" "${CMAKE_SOURCE_DIR}/game" "${ROM_NAME}")

add_executable(ShadowrunRecomp
    ${RUNNER_SOURCES}
    ${GENERATED_SOURCES}
    "${CMAKE_SOURCE_DIR}/game/${PREFIX}_spec.c")

set_target_properties(ShadowrunRecomp PROPERTIES OUTPUT_NAME "ShadowrunRecomp")

target_include_directories(ShadowrunRecomp PRIVATE
    "${RUNNER_ROOT}" "${RUNNER_ROOT}/include" "${RUNNER_ROOT}/video"
    "${RUNNER_ROOT}/audio"
    "${RUNNER_ROOT}/external/ymfm/src"
    "${RUNNER_ROOT}/external/superzazu"
    "${RUNNER_ROOT}/external/clowncommon"
    "${RUNNER_ROOT}/external/minicoro"
    "${RECOMP_ROOT}/recompiler/src"
    "${CMAKE_SOURCE_DIR}/game"
    ${SDL2_PARENT_INCLUDE_DIRS})

# Force-include the compatibility header (see game/shadowrun_compat.h).
if(MSVC)
    target_compile_options(ShadowrunRecomp PRIVATE "/FI${CMAKE_SOURCE_DIR}/game/shadowrun_compat.h")
else()
    target_compile_options(ShadowrunRecomp PRIVATE -include "${CMAKE_SOURCE_DIR}/game/shadowrun_compat.h")
endif()

target_compile_definitions(ShadowrunRecomp PRIVATE
    INCLUDE_GENERATED_CODE=1
    ENABLE_RECOMPILED_CODE=1
    OWN_BACKEND=1
    SHADOWRUN_BUILD_VERSION="${SHADOWRUN_BUILD_VERSION}")

target_link_libraries(ShadowrunRecomp PRIVATE SDL2::SDL2main SDL2::SDL2)
if(WIN32)
    target_link_libraries(ShadowrunRecomp PRIVATE ws2_32 comdlg32)
    if(EXISTS "${SDL2_BUNDLED}/lib/x64/SDL2.dll")
        add_custom_command(TARGET ShadowrunRecomp POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${SDL2_BUNDLED}/lib/x64/SDL2.dll" "$<TARGET_FILE_DIR:ShadowrunRecomp>"
            COMMENT "Copying SDL2.dll next to the executable")
    endif()
endif()

# Shared launcher UI (Dear ImGui) - optional: the game runs without it, and the
# submodule is only present once `git submodule update --init` has fetched it.
if(EXISTS "${CMAKE_SOURCE_DIR}/recomp-ui/recomp_ui.cmake")
    include("${CMAKE_SOURCE_DIR}/recomp-ui/recomp_ui.cmake")
    recomp_target_launcher_ui(ShadowrunRecomp CONSOLE genesis)
    message(STATUS "recomp-ui: launcher enabled")
else()
    message(STATUS "recomp-ui: not present, building without the launcher")
endif()

# --- dev-only co-simulation target (recomp vs the Tier-3 interpreter) --------
# docs/COSIM.md pairing #1: reports the first divergence between the recompiled
# code and the clean-room interpreter. Never shipped.
option(SHADOWRUN_BUILD_COSIM "Build the recomp-vs-interpreter co-sim target" OFF)
if(SHADOWRUN_BUILD_COSIM)
    # The recompiler writes the per-instruction cost table here, but the
    # framework's generated-sources helper does not copy it into generated/.
    set(COSIM_CYCLES "${CMAKE_CURRENT_BINARY_DIR}/generation-stage/${PREFIX}/${PREFIX}_cycles.c")
    # Produced by the generation step during the build, so it does not exist at
    # configure time; add it unconditionally.
    set_source_files_properties("${COSIM_CYCLES}" PROPERTIES GENERATED TRUE)
    list(APPEND COSIM_EXTRA "${COSIM_CYCLES}")
    set(COSIM_SOURCES
        ${COSIM_EXTRA}
        "${RUNNER_ROOT}/game_cycles.c"
        "${RUNNER_ROOT}/frame_snapshots.c"
        "${RUNNER_ROOT}/cosim.c"
        "${RUNNER_ROOT}/cosim_state.c"
        "${RUNNER_ROOT}/cosim_visible.c"
        "${RUNNER_ROOT}/cosim_cycles.c")
    add_executable(ShadowrunRecomp_cosim
        ${RUNNER_SOURCES} ${GENERATED_SOURCES} ${COSIM_SOURCES}
        "${CMAKE_SOURCE_DIR}/game/${PREFIX}_spec.c")
    target_compile_definitions(ShadowrunRecomp_cosim PRIVATE
        INCLUDE_GENERATED_CODE=1 ENABLE_RECOMPILED_CODE=1 OWN_BACKEND=1
        GENESIS_COSIM=1
        SHADOWRUN_BUILD_VERSION="${SHADOWRUN_BUILD_VERSION}")
    target_include_directories(ShadowrunRecomp_cosim PRIVATE
        "${RUNNER_ROOT}" "${RUNNER_ROOT}/include" "${RUNNER_ROOT}/video"
        "${RUNNER_ROOT}/audio" "${RUNNER_ROOT}/external/ymfm/src"
        "${RUNNER_ROOT}/external/superzazu" "${RUNNER_ROOT}/external/clowncommon"
        "${RUNNER_ROOT}/external/minicoro" "${RECOMP_ROOT}/recompiler/src"
        "${CMAKE_SOURCE_DIR}/game" ${SDL2_PARENT_INCLUDE_DIRS})
    target_link_libraries(ShadowrunRecomp_cosim PRIVATE SDL2::SDL2main SDL2::SDL2)
    if(WIN32)
        target_link_libraries(ShadowrunRecomp_cosim PRIVATE ws2_32 comdlg32)
    endif()
endif()
