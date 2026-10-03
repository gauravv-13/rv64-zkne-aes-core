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

.PHONY: all sim test lint clean

all: test

# ---------------------------------------------------------------------------
# make sim : run the legacy program and print the register dump
# ---------------------------------------------------------------------------
LEGACY_SIM := $(BUILD)/sim_legacy_aes.vvp

$(LEGACY_SIM): $(RTL) $(TB) $(RTL_F)
	@mkdir -p $(BUILD)
	$(IVERILOG) -g2005 -s pipe_tb -DLEGACY_AES -o $@ -c $(RTL_F) $(TB)

sim: $(LEGACY_SIM)
	@mkdir -p $(BUILD)/legacy
	$(VVP) -n $(LEGACY_SIM) +IMEM=tests/legacy/program.hex \
	    +OUT=$(BUILD)/legacy/regs.txt +MAX_CYCLES=200 +ZERO_WORD_STOP \
	    +VCD=$(BUILD)/legacy/pipeline.vcd
	@echo "Register dump: $(BUILD)/legacy/regs.txt"
	@cat $(BUILD)/legacy/regs.txt

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
