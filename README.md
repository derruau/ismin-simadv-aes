# ISMIN 3A - Advanced Simulation

## Description

This project contains the SystemVerilog testbenches and AES RTL used for the [Mines Saint-Etienne's](https://emse.fr) ISMIN 3A Advanced Simulation practical sessions (TD1–TD4). It covers AES-128/AES-256 encryption and decryption verification, AHB interface testing, and SystemVerilog assertions. Python reference implementations are used to validate simulation results through a C/DPI bridge.

## Installation

The project requires QuestaSim/ModelSim, GCC, Python 3.10, and its development libraries. On the course environment, initialize the required modules and install the Python dependencies:

```bash
chmod +x scripts/*.sh
source scripts/init_modules.sh # If on the school server
python3.10 -m pip install -r requirements.txt
bash scripts/build_c.sh
```

## Usage

Use the provided build script to compile and run the simulations:

```bash
./scripts/build.sh TD1 -tcr
```

Replace `TD1` with `TD2`, `TD3`, or `TD4` to select another practical session. Add `-g` to launch the graphical interface or `-v` to enable coverage.

Run `./scripts/build.sh -h` to see all available options.
