IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
VIVADO ?= vivado
SRC_DIR := neu_risc_v.srcs/sources_1
TB_DIR := neu_risc_v.srcs/sim_1/tb
RTL_DIR := $(SRC_DIR)/rtl
RTL := $(wildcard $(RTL_DIR)/*.v)
TESTS := tb_rv32_soc tb_demo tb_rv32i tb_alu tb_control tb_regfile tb_memory tb_pipeline_edges
TEST_TARGETS := $(addprefix test-,$(TESTS))
REVIEW_TESTS := tb_review3 tb_review4 tb_review6 tb_review7 tb_review8
REVIEW_TARGETS := $(addprefix test-,$(REVIEW_TESTS))
WAVE_TARGETS := $(addprefix wave-,$(TESTS) $(REVIEW_TESTS))
WAVE_SOURCE = $(if $(filter 1,$(WAVE)),scripts/wave_dump.sv)
WAVE_TOP = $(if $(filter 1,$(WAVE)),-s wave_dump)

.PHONY: test test-review wave $(WAVE_TARGETS) $(TEST_TARGETS) $(REVIEW_TARGETS) synth-check synth-xilinx vivado-project
test: $(TEST_TARGETS) $(REVIEW_TARGETS)
test-review: $(REVIEW_TARGETS)
wave: wave-tb_rv32_soc

$(WAVE_TARGETS): wave-%:
	$(MAKE) test-$* WAVE=1

$(TEST_TARGETS): TEST_SOURCE_DIR := $(TB_DIR)
$(REVIEW_TARGETS): TEST_SOURCE_DIR := review

# 每个测试都可单独运行，例如 make test-tb_alu；失败时同样显示并保留日志。
$(TEST_TARGETS) $(REVIEW_TARGETS): test-%: build/demo.mem
	$(IVERILOG) -g2012 -Wall -I $(RTL_DIR) -I $(TB_DIR) -s $* $(WAVE_TOP) -o build/$* $(RTL) $(TEST_SOURCE_DIR)/$*.sv $(WAVE_SOURCE)
	(cd build && $(VVP) $* $(if $(filter 1,$(WAVE)),+wave=$*.vcd) > $*.log 2>&1) || { cat build/$*.log; exit 1; }
	cat build/$*.log

build/demo.mem: $(SRC_DIR)/mem/demo.mem
	mkdir -p build
	cp $< $@

synth-check:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv -I$(RTL_DIR) $(RTL); hierarchy -check -top rv32_soc; synth -top rv32_soc; check -assert' > build/yosys.log

synth-xilinx:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv -I$(RTL_DIR) $(RTL); synth_xilinx -top rv32_soc -family xc7; check -assert' > build/yosys-xilinx.log

vivado-project:
	@test -n "$(PART)" || { echo '请指定准确器件型号：make vivado-project PART=<器件型号>'; exit 1; }
	mkdir -p build
	cd build && $(VIVADO) -mode batch -source ../scripts/create_project.tcl -tclargs "$(PART)"
