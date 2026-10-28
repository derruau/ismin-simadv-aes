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
# Precheck
#============================================================

if [ ! -f $SHARED_LIB_PATH ];
then
    echo "========== [ SHARED LIBRARY COMPILATION ] =========="
    echo "Shared library $SHARED_LIB_PATH not found, compiling it!"
    ./scripts/build_c.sh
fi

#============================================================
# Compilation script
#============================================================

STOP_SCRIPT=0

if [[ $OPT_COMPILE_AES = true ]]; then
    echo "========== [ SOURCES COMPILATION ] =========="

    mkdir -p libs/work
    vdel -lib libs/work/ -all
    vlib libs/work
    vmap work libs/work

    while IFS= read -r -d '' path; do
        _VLOG_RESULT=$(vlog -sv -work work +acc "$path" 2>&1) || STOP_SCRIPT=1
        _VLOG_RESULT=$(echo "$_VLOG_RESULT" | grep 'Error')

        echo "$(basename "$path"):"
        echo "$_VLOG_RESULT" | sed 's/^/    /'

    done < <(find "$RTL_FOLDER_PATH" -type f \( -name '*.sv' -o -name '*.v' \) -print0)
fi

# Compile the AES testbench
if [[ $OPT_COMPILE_TB = true ]]; then
    echo "========== [ TESTBENCH COMPILATION ] =========="
    _VLOG_RESULT=$(vlog -sv -work work +acc "$TB_PATH" 2>&1) || STOP_SCRIPT=1
    _VLOG_RESULT=$(echo "$_VLOG_RESULT" | grep 'Error')

    echo "$(basename $TB_PATH):"
    echo "$_VLOG_RESULT" | sed 's/^/    /'
fi

# Creates the coverage file
if [[ -n "$OPT_COVERAGE" ]]; then
    echo "========== [ COVERAGE ] =========="
    vopt $TB_MODULE_NAME -o ${TB_MODULE_NAME}_cov -work work +cover=sbcfte

    $TB_MODULE_NAME=${TB_MODULE_NAME}_cov
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

    mkdir -p logs

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
        -wlf logs/vsim.wlf \
        -l logs/transcript \
        -modelsimini logs/modelsim.ini
fi