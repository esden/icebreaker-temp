PROJ = top
BOARD ?= icebreaker
PIN_DEF = top-$(BOARD).pcf
DEVICE = up5k
PACKAGE = sg48

ARACHNE = arachne-pnr 
ARACHNE_ARGS = 
NEXTPNR = nextpnr-ice40
NEXTPNR_ARGS =
ICEPACK = icepack
ICETIME = icetime
ICEPROG = iceprog

PNR ?= arachne

ICE40_LIBS=$(shell yosys-config --datdir/ice40/cells_sim.v)

OBJS=\
	hub75_bcm.v \
	hub75_blanking.v \
	hub75_framebuffer.v \
	hub75_scan.v \
	hub75_shift.v \
	hub75_top.v \
	pgen.v \
	sysmgr.v \
	sim_spram.v

TESTBENCHES=\
	hub75_top_tb

all: $(PROJ).bin $(TESTBENCHES)

%_tb: %_tb.v $(ICE40_LIBS) $(OBJS)
	iverilog -Wall -DSIM=1 -o $@ $(ICE40_LIBS) $(OBJS) $<

%.blif %.json: %.v $(OBJS)
	yosys -p 'synth_ice40 -top $(PROJ) -blif $*.blif -json $*.json' $< $(OBJS)

ifeq ($(PNR),next)
%.asc: $(PIN_DEF) %.json
	$(NEXTPNR) $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $*.json --pcf $(PIN_DEF) --asc $@
else
%.asc: $(PIN_DEF) %.blif
	$(ARACHNE) $(ARACHNE_ARGS) -d $(subst up,,$(subst hx,,$(subst lp,,$(DEVICE)))) -o $@ -p $^ -P $(PACKAGE)
endif

%.bin: %.asc
	$(ICEPACK) $< $@

%.rpt: %.asc
	$(ICETIME) -d $(DEVICE) -mtr $@ $<

prog: $(PROJ).bin
	$(ICEPROG) -S $<

sudo-prog: $(PROJ).bin
	@echo 'Executing prog as root!!!'
	sudo $(ICEPROG) -S $<

clean:
	rm -f $(PROJ).blif $(PROJ).json $(PROJ).asc $(PROJ).rpt $(PROJ).bin $(TESTBENCHES) *.vcd

.SECONDARY:
.PHONY: all prog clean
