# ===============================================
# Makefile for VCS + Verdi Simulation Environment
# ===============================================
export project_name = lenet5_top

CC := /usr/bin/gcc-4.8
CXX := /usr/bin/g++-4.8

# Top module (can be changed later)
TOP_MODULE ?= tb_$(project_name)

# Platform definition for Verdi/VCS PLI files
PLATFORM = LINUX64

# Waveform file
waveform = $(project_name).fsdb

# Auto-load waveform if exists
ifeq ($(waveform), $(wildcard $(waveform)))
	load_wave = -ssf $(waveform)
endif

# Default target
all: all_vcs

# ===== VCS Flow =====
all_vcs: comp_vcs run_vcs

comp_vcs:
	vcs -sverilog \
	    -full64 \
	    -lca \
	    -kdb \
	    -debug_access+all \
	    -LDFLAGS -rdynamic \
	    -P $(VERDI_HOME)/share/PLI/VCS/$(PLATFORM)/novas.tab \
	    $(VERDI_HOME)/share/PLI/VCS/$(PLATFORM)/pli.a \
	    -f ./filelist.f \
	    +vcs+lic+wait \
	    +v2k \
	    +define+DUMP_ARRAY \
	    +memcbk \
	    -top $(TOP_MODULE) \
	    -l compile.log

run_vcs:
	./simv -ucli -i ../scripts/dump_fsdb_vcs.tcl \
		+fsdb+autoflush \
		-l sim.log

run_vcs_tb:
	./simv \
		-l sim.log

# ===== Debug Using Verdi =====
dbg:
	verdi -sv \
		-f ./filelist.f \
		-top $(TOP_MODULE) \
		$(load_wave) \
		-nologo

# ===== Clean Simulation Files =====
clean:
	rm -rf *.fsdb *.log *.rc csrc simv ucli.key \
		*.daidir verdiLog *.conf all
