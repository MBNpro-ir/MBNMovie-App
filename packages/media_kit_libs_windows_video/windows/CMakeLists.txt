# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# Pin the tested baseline-x86_64 build (no x86-64-v3 CPU requirement).
# 2023 libmpv produced visible startup stutter in the isolated production player.
set(LIBMPV "mpv-dev-x86_64-20261021-git-e471496c56.7z")
set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261021/${LIBMPV}")
set(LIBMPV_SHA256 "efc719eff3dc5954b4a5efc800632808bcec01cc9034940dd14e5eb7fe9ea633")
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
# Version the extracted directory so an existing build cannot retain the old DLL.
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv-20261021-git-e471496c56")

file(DOWNLOAD "${LIBMPV_URL}" "${LIBMPV_ARCHIVE}"
  EXPECTED_HASH "SHA256=${LIBMPV_SHA256}" TLS_VERIFY ON STATUS LIBMPV_DOWNLOAD_STATUS)
list(GET LIBMPV_DOWNLOAD_STATUS 0 LIBMPV_DOWNLOAD_CODE)
if(NOT LIBMPV_DOWNLOAD_CODE EQUAL 0)
  message(FATAL_ERROR "Unable to fetch verified libmpv: ${LIBMPV_DOWNLOAD_STATUS}")
endif()

if(NOT EXISTS "${LIBMPV_SRC}/libmpv-2.dll")
  file(MAKE_DIRECTORY "${LIBMPV_SRC}")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LIBMPV_ARCHIVE}"
    WORKING_DIRECTORY "${LIBMPV_SRC}" RESULT_VARIABLE LIBMPV_EXTRACT_RESULT)
  if(NOT LIBMPV_EXTRACT_RESULT EQUAL 0)
    message(FATAL_ERROR "Unable to extract libmpv")
  endif()
  file(COPY "${LIBMPV_SRC}/include/mpv/" DESTINATION "${LIBMPV_SRC}/include")
endif()
file(SHA256 "${LIBMPV_SRC}/libmpv-2.dll" LIBMPV_DLL_SHA256)
if(NOT LIBMPV_DLL_SHA256 STREQUAL "04e4d27dc385dc18ddd93fbe69c75e635b864f3c6ec53a9122df54c2f7842f4a")
  message(FATAL_ERROR "Extracted libmpv failed SHA256 verification")
endif()

# ------------------------------------------------------------------------------

# ANGLE archive containing the pre-built shared libraries & headers.
set(ANGLE "ANGLE.7z")

# Download URL & MD5 hash of the ANGLE archive.
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")

# Download location of the ANGLE archive.
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_verify(
  ${ANGLE_URL}
  ${ANGLE_MD5}
  ${ANGLE_ARCHIVE}
)

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

# Extract the ANGLE archive.
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../MPV-NOTICE.txt"
  "${CMAKE_CURRENT_SOURCE_DIR}/../MPV-LICENSE.GPL.txt"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
