# Pipelined RV64 core - build and test.
# Tools: Icarus Verilog 13 (iverilog/vvp), Verilator 5, Python 3 (Homebrew on macOS).

IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
PYTHON    ?= python3

BUILD     := build
RTL_F     := rtl/files.f
RTL       := $(shell cat $(RTL_F))
TB        := tb/pipe_tb.v

.PHONY: all sim vcd test lint clean

all: test

# ---------------------------------------------------------------------------
# make sim : run the legacy program and print the register dump
#            (make sim PROG=<file> runs another program, see below)
# ---------------------------------------------------------------------------
LEGACY_SIM := $(BUILD)/sim_legacy_aes_reset_pc0.vvp

$(LEGACY_SIM): $(RTL) $(TB) $(RTL_F)
	@mkdir -p $(BUILD)
	$(IVERILOG) -g2005 -s pipe_tb -DLEGACY_AES -Ppipe_tb.RESET_PC=0 -o $@ -c $(RTL_F) $(TB)

ifeq ($(PROG),)
sim: $(LEGACY_SIM)
	@mkdir -p $(BUILD)/legacy
	$(VVP) -n $(LEGACY_SIM) +IMEM=tests/legacy/program.hex \
	    +OUT=$(BUILD)/legacy/regs.txt +MAX_CYCLES=200 +ZERO_WORD_STOP \
	    +VCD=$(BUILD)/legacy/pipeline.vcd
	@echo "Register dump: $(BUILD)/legacy/regs.txt"
	@cat $(BUILD)/legacy/regs.txt
else
# make sim PROG=<file.S|file.elf> : run a program, full VCD in build/vcd/
sim:
	$(PYTHON) scripts/sim_prog.py --vcd $(BUILD)/vcd/$(basename $(notdir $(PROG)))_full.vcd $(PROG)
endif

# ---------------------------------------------------------------------------
# make vcd PROG=<file.S|file.elf> : VCD of the Zkne unit only (for toggle-count
# leakage analysis) -> build/vcd/<name>_zkne.vcd
# ---------------------------------------------------------------------------
vcd:
	@test -n "$(PROG)" || (echo "usage: make vcd PROG=<file.S|file.elf>"; exit 1)
	$(PYTHON) scripts/sim_prog.py --vcd-zkne $(BUILD)/vcd/$(basename $(notdir $(PROG)))_zkne.vcd $(PROG)

# ---------------------------------------------------------------------------
# make test : run every test, print a pass/fail summary (K=<substring> filters)
# ---------------------------------------------------------------------------
test:
	$(PYTHON) scripts/run_tests.py $(if $(K),-k "$(K)")

# ---------------------------------------------------------------------------
# make lint : Verilator lint of the synthesizable core (testbench excluded)
# ---------------------------------------------------------------------------
lint:
	$(VERILATOR) --lint-only -Wall --top-module processor \
	    scripts/lint_waivers.vlt -f $(RTL_F)

clean:
	rm -rf $(BUILD) obj_dir
