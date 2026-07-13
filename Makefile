ERLC ?= erlc
MIX ?= mix
PYTHON ?= python3

ATOMVM_BUILD ?= ../atomvm_for_picorv32/AtomVM/build/generic_unix_full
HOST_ATOMVM ?= $(ATOMVM_BUILD)/src/AtomVM
ATOMVMLIB ?= $(ATOMVM_BUILD)/libs/atomvmlib.avm
ESTDLIB ?= $(ATOMVM_BUILD)/libs/estdlib/src/estdlib.avm
EXAVMLIB ?= $(ATOMVM_BUILD)/libs/exavmlib/lib/exavmlib.avm
EUNIT_BEAM ?= $(ATOMVM_BUILD)/libs/etest/src/beams/eunit.beam
PACKBEAM ?= ../atomvm_for_picorv32/fw/packbeam

HOST_ATOMVM_BUILD_DIR := tmp/host_atomvm_unit
HOST_ATOMVM_UNIT := micro_phoenix_atomvm_unit
HOST_ATOMVM_UNIT_SRC := test_atomvm/$(HOST_ATOMVM_UNIT).erl
HOST_ATOMVM_UNIT_BEAM := $(HOST_ATOMVM_BUILD_DIR)/$(HOST_ATOMVM_UNIT).beam
HOST_ATOMVM_UNIT_AVM := $(HOST_ATOMVM_BUILD_DIR)/$(HOST_ATOMVM_UNIT).avm

HOST_ATOMVM_APP_BEAMS := \
	_build/dev/lib/micro_phoenix/ebin/Elixir.MicroPhoenix.Request.beam \
	_build/dev/lib/micro_phoenix/ebin/Elixir.Template.beam

.PHONY: host-atomvm-unit host-atomvm-unit-avm clean-host-atomvm-unit

host-atomvm-unit: host-atomvm-unit-avm
	@test -x "$(HOST_ATOMVM)" || (echo "HOST_ATOMVM not executable: $(HOST_ATOMVM)" >&2; exit 127)
	@test -f "$(ATOMVMLIB)" || (echo "missing atomvmlib: $(ATOMVMLIB)" >&2; exit 127)
	@test -f "$(ESTDLIB)" || (echo "missing estdlib: $(ESTDLIB)" >&2; exit 127)
	@test -f "$(EXAVMLIB)" || (echo "missing exavmlib: $(EXAVMLIB)" >&2; exit 127)
	$(HOST_ATOMVM) $(HOST_ATOMVM_UNIT_AVM) $(ATOMVMLIB) $(ESTDLIB) $(EXAVMLIB)

host-atomvm-unit-avm: $(HOST_ATOMVM_UNIT_SRC)
	$(MIX) deps.get
	$(MIX) compile
	@mkdir -p $(HOST_ATOMVM_BUILD_DIR)
	$(ERLC) -o $(HOST_ATOMVM_BUILD_DIR) $(HOST_ATOMVM_UNIT_SRC)
	@test -f "$(PACKBEAM)" || (echo "missing packbeam: $(PACKBEAM)" >&2; exit 127)
	@test -f "$(EUNIT_BEAM)" || (echo "missing AtomVM eunit beam: $(EUNIT_BEAM)" >&2; exit 127)
	$(PYTHON) $(PACKBEAM) create -s $(HOST_ATOMVM_UNIT) $(HOST_ATOMVM_UNIT_AVM) $(HOST_ATOMVM_UNIT_BEAM) $(EUNIT_BEAM) $(HOST_ATOMVM_APP_BEAMS)
	@echo "Host AtomVM unit AVM: $(HOST_ATOMVM_UNIT_AVM)"

clean-host-atomvm-unit:
	rm -rf $(HOST_ATOMVM_BUILD_DIR)
