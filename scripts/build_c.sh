#! /bin/bash

# This script builds the C shared library that modelsim interfaces with.

#============================================================
# Variables
#============================================================

# Targetted python version to link. 
# Formatting: Do not include the minor version change
# --- [ EXAMPLE] ---
# TARGET_PY_VER=3.10 # Do NOT input 3.10.14
TARGET_PY_VER=3.10

# Path to the C file relative to the project's root
# --- [ EXAMPLE] ---
# C_FILE_PATH=TP/call_python.c
C_FILE_PATH=bench/call_python.c

#============================================================
# Function definition
#============================================================

# Check that a command is installed on the computer
# Usage: require_command [COMMAND_NAME]
require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Error: required command "%s" not found in PATH\n' "$1" >&2
        exit 1
    fi
}

# Check that a version string match another one
# Usage check_versions [TARGETTED_VERSION] [TESTED_VERSION] [COMMAND_NAME]
check_versions() {
    if [ ! "$1" = "$2" ]; then
        printf 'Error: `%s` version does not match the target version! (%s instead of %s)\n' "$3" "$2" "$1" >&2
        exit 1
    fi
}

#============================================================
# Prechecks - do commands exist
#============================================================

PY="python${TARGET_PY_VER}"
PY_CONFIG="python${TARGET_PY_VER}-config"

require_command $PY
require_command $PY_CONFIG
require_command gcc

#============================================================
# Prechecks - do python versions match ?
#============================================================


PY_VER=$("$PY" --version | sed 's/Python \([0-9]*\.[0-9]*\).*/\1/')
PY_CFG_VER=$(basename "$("$PY_CONFIG" --includes| sed 's/-I\(.*\) /\1/')" | sed 's/python\([0-9]*\.[0-9]*\)/\1/')

check_versions $TARGET_PY_VER $PY_VER $PY
check_versions $TARGET_PY_VER $PY_CFG_VER $PY_CONFIG

#============================================================
# Compilation script
#============================================================

PY_SO=$(find $("$PY_CONFIG" --prefix) -name "*${TARGET_PY_VER}.so" | tail -1)

# Checking that the shared lib was found.
if [ ! -f "$PY_SO" ];
then
    echo "Targetted python version's shared lib could not be found"
    exit 1
fi

# Fix because -Wl,-rpath isn't guaranteed with $PY_CONFIG
PY_LIBDIR=$("$PY" -c 'import sysconfig; print(sysconfig.get_config_var("LIBDIR"))')

# Compilation command
gcc \
    -DPYTHON_SHARED_LIB=\"$(echo ${C_FILE_PATH%.*}).so\" \
    -fPIC -shared \
    $("$PY_CONFIG" --includes) \
    -o $(echo ${C_FILE_PATH%.*}).so \
    $C_FILE_PATH \
    -Wl,--no-undefined \
    $("$PY_CONFIG" --ldflags --embed) \
    -Wl,-rpath,"$PY_LIBDIR"