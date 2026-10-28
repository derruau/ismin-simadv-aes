#! /bin/bash

# This script compiles and launches the simulation for the sources and the testbench.
# It has multiple options which you can view by typing ./build.sh without any arguments.

#============================================================
# Variables
#============================================================

# Testbench module name.
# --- [ EXAMPLE] ---
# If the verilog module is defined as:
# module aes_tb ();
# ...
# endmodule : aes_tb
# Then the variable should be set to:
# TB_MODULE_NAME=aes_tb
TB_MODULE_NAME=aes_tb

# Testbench file path
# --- [ EXAMPLE] ---
# TB_PATH='./bench/%TD%/aes_tb.sv' # %TD% is a placeholder argument
TB_PATH='./bench/%TD%/aes_tb.sv' # %TD% is a placeholder argument

# C shared library path 
# Formatting: Do NOT include the .so extension to this path
# --- [ EXAMPLE] ---
# SHARED_LIB_PATH=./TP/call_python # For the file in ./TP/call_python.so
SHARED_LIB_PATH=./bench/call_python

# Source folder where the AES module is located
# --- [ EXAMPLE] ---
# RTL_FOLDER_PATH='./rtl/'
RTL_FOLDER_PATH=./rtl/

#============================================================
# Private Variables - DO NOT CHANGE
#============================================================

# Location of the file which generates pairs
# of test vectors for the first TD.
# --- [ EXAMPLE] ---
# TD1_GEN_TEST_VECTORS_SCRIPT=scripts/gen_aes_test_vectors.py
TD1_GEN_TEST_VECTORS_SCRIPT=scripts/gen_aes_test_vectors.py

# Location of the logs folder, where info about modelsim is stored
# --- [ EXAMPLE] ---
# LOGS_PATH=./logs/
LOGS_PATH=./logs/

# Location of the modelsim.ini file
# --- [ EXAMPLE] ---
# MODELSIM_INI_PATH="$LOGS_PATH/modelsim.ini"
MODELSIM_INI_PATH="$LOGS_PATH/modelsim.ini"

# Location of the transcript file
# --- [ EXAMPLE] ---
# TRANSCRIPT_PATH="$LOGS_PATH/transcript"
TRANSCRIPT_PATH="$LOGS_PATH/transcript"

# Location of the vsim.wlf file
# --- [ EXAMPLE] ---
# WLF_PATH="$LOGS_PATH/vsim.wlf"
WLF_PATH="$LOGS_PATH/vsim.wlf"


#============================================================
# Parameter parsing
#============================================================

# List of valid TDs
VALID_TDS=(TD1 TD2 TD3 TD4)

# Default options
OPT_COMPILE_AES=false
OPT_GUI="-c"
OPT_RUN=false
OPT_COMPILE_TB=false
OPT_COVERAGE=""

# Display help
usage() {
    echo "Usage: $0 <TD> [options]"
    echo
    echo "Available TDs: ${VALID_TDS[*]}"
    echo
    echo "Options:"
    echo "  -c : AES compilation"
    echo "  -g : Launch GUI"
    echo "  -r : Run simulation"
    echo "  -t : Testbench compilation"
    echo "  -v : Enable coverage"
    echo "  -h : Display help"
    echo
    echo "Examples:"
    echo "  $0 TD1 -tcrg"
    echo "  $0 -tcrg TD1"
}

# Extract TD and preserve options
TD=""
ARGS=()

for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
        ARGS+=("$arg")
    elif [[ -z "$TD" ]]; then
        TD="$arg"
    else
        echo "Error: Unexpected argument '$arg'" >&2
        usage
        exit 1
    fi
done

# Validate TD
if [[ -z "$TD" ]]; then
    echo "Error: No TD specified." >&2
    usage
    exit 1
fi

if [[ ! " ${VALID_TDS[*]} " =~ " ${TD} " ]]; then
    echo "Error: Invalid TD '$TD'." >&2
    echo "Valid TDs: ${VALID_TDS[*]}" >&2
    exit 1
fi

# Parse options
set -- "${ARGS[@]}"
OPTIND=1

while getopts ":grcvth" opt; do
    case "$opt" in
        g) OPT_GUI="-gui" ;;
        c) OPT_COMPILE_AES=true ;;
        t) OPT_COMPILE_TB=true ;;
        r) OPT_RUN=true ;;
        v) OPT_COVERAGE="-coverage" ;;
        h) usage; exit 0 ;;
        \?)
            echo "Error: Invalid option '-$OPTARG'" >&2
            usage
            exit 1
            ;;
    esac
done

echo "Selected TD: $TD"

# Setting the definitive TB path
TB_PATH="${TB_PATH//%TD%/$TD}"

#============================================================
# Prechecks for each TDs
#============================================================

# For the first TD, we should generate the plaintext/ciphertext pairs
if [[ $TD == "TD1" ]]; then
    echo "Initializing test vectors..."
    python $TD1_GEN_TEST_VECTORS_SCRIPT || exit 1
fi

#============================================================
# ModelSim initialization
#============================================================

mkdir -p "$LOGS_PATH"

if [[ ! -f "$MODELSIM_INI_PATH" ]]; then
    echo "Initializing ModelSim configuration..."
    (cd "$LOGS_PATH" && vmap -c) || exit 1
fi

# Sets the MODELSIM variable, in which modelsim.ini is.
export MODELSIM="$(realpath "$MODELSIM_INI_PATH")"

#============================================================
# Checking the shared library's existence
#============================================================

if [ ! -f "$SHARED_LIB_PATH.so" ];
then
    echo "========== [ SHARED LIBRARY COMPILATION ] =========="
    echo "Shared library $SHARED_LIB_PATH not found, compiling it!"
    ./scripts/build_c.sh || exit 1
fi

#============================================================
# Creating the work library
#============================================================

mkdir -p libs

if [[ ! -d libs/work/_info ]]; then
    echo "========== [ CREATING WORK LIBRARY ] =========="
    vdel -lib libs/work/ -all
    vlib libs/work || exit 1
fi

vmap work "$(realpath libs/work)" || exit 1

#============================================================
# Compilation script
#============================================================

STOP_SCRIPT=0

if [[ $OPT_COMPILE_AES = true ]]; then
    echo "========== [ SOURCES COMPILATION ] =========="

    while IFS= read -r -d '' path; do
        _VLOG_RESULT=$(vlog -sv -work work +acc "$path" 2>&1) || STOP_SCRIPT=1

        echo "$(basename "$path"):"
        echo "$_VLOG_RESULT" | grep -Ei '^\*\* (error|fatal|warning|note):' | sed 's/^/    /' || true
        echo "$_VLOG_RESULT" | grep -E 'Errors: [0-9]+, Warnings: [0-9]+' | tail -n 1 | sed 's/^/    /' || true

    done < <(find "$RTL_FOLDER_PATH" -type f \( -name '*.sv' -o -name '*.v' \) -print0)
fi

# Compile the AES testbench
if [[ $OPT_COMPILE_TB = true ]]; then
    echo "========== [ TESTBENCH COMPILATION ] =========="
    _VLOG_RESULT=$(vlog -sv -work work +acc "$TB_PATH" 2>&1) || STOP_SCRIPT=1

    echo "$(basename $TB_PATH):"
    echo "$_VLOG_RESULT" | grep -Ei '^\*\* (error|fatal|warning|note):' | sed 's/^/    /' || true
    echo "$_VLOG_RESULT" | grep -E 'Errors: [0-9]+, Warnings: [0-9]+' | tail -n 1 | sed 's/^/    /' || true

fi

# Creates the coverage file
if [[ -n "$OPT_COVERAGE" && "$OPT_RUN" == true && "$STOP_SCRIPT" == 0 ]]; then
    echo "========== [ COVERAGE ] =========="

    if ! vopt "$TB_MODULE_NAME" \
        -o "${TB_MODULE_NAME}_cov" \
        -work work \
        +cover=sbcfte; then
        echo "ERROR: Coverage optimization failed." >&2
        exit 1
    fi

    TB_MODULE_NAME="${TB_MODULE_NAME}_cov"
fi

#============================================================
# Simulation
#============================================================

if [[ $OPT_RUN = true ]]; then
    echo "========== [ SIMULATION ] =========="

    if [[ $STOP_SCRIPT = "1" ]]; then
        echo "ERRORS IN COMPILATION WERE DETECTED, EXITING..."
        exit 1
    fi

    vsim \
        $TB_MODULE_NAME \
        $OPT_COVERAGE \
        $OPT_GUI \
        -t 1ps \
        -64 \
        -sv_lib $SHARED_LIB_PATH \
        -voptargs=+acc \
        -work work \
        -do "run -all" \
        -wlf $WLF_PATH \
        -l $TRANSCRIPT_PATH
fi