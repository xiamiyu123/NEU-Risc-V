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

.PHONY: test $(TEST_TARGETS) synth-check synth-xilinx vivado-project
test: $(TEST_TARGETS)

# 每个测试都可单独运行，例如 make test-tb_alu；失败时同样显示并保留日志。
$(TEST_TARGETS): test-%: build/demo.mem
	$(IVERILOG) -g2012 -Wall -I $(RTL_DIR) -I $(TB_DIR) -s $* -o build/$* $(RTL) $(TB_DIR)/$*.sv
	(cd build && $(VVP) $* > $*.log 2>&1) || { cat build/$*.log; exit 1; }
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
