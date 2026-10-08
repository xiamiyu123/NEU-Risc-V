IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
VIVADO ?= vivado
SRC_DIR := neu_risc_v.srcs/sources_1
TB_DIR := neu_risc_v.srcs/sim_1/tb
RTL := $(SRC_DIR)/rtl/rv32_core.v $(SRC_DIR)/rtl/rv32_sync_mem.v $(SRC_DIR)/rtl/rv32_soc.v

.PHONY: test synth-check synth-xilinx vivado-project
test:
	mkdir -p build
	cp $(SRC_DIR)/mem/demo.mem build/demo.mem
	$(IVERILOG) -g2012 -Wall -I $(TB_DIR) -s tb_rv32_soc -o build/tb_rv32_soc $(RTL) $(TB_DIR)/tb_rv32_soc.sv
	cd build && $(VVP) tb_rv32_soc
	$(IVERILOG) -g2012 -Wall -I $(TB_DIR) -s tb_demo -o build/tb_demo $(RTL) $(TB_DIR)/tb_demo.sv
	cd build && $(VVP) tb_demo
	$(IVERILOG) -g2012 -Wall -I $(TB_DIR) -s tb_rv32i -o build/tb_rv32i $(RTL) $(TB_DIR)/tb_rv32i.sv
	cd build && $(VVP) tb_rv32i

synth-check:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv $(RTL); hierarchy -check -top rv32_soc; synth -top rv32_soc; check -assert' > build/yosys.log

synth-xilinx:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv $(RTL); synth_xilinx -top rv32_soc -family xc7; check -assert' > build/yosys-xilinx.log

vivado-project:
	@test -n "$(PART)" || { echo '请指定准确器件型号：make vivado-project PART=<器件型号>'; exit 1; }
	mkdir -p build
	cd build && $(VIVADO) -mode batch -source ../scripts/create_project.tcl -tclargs "$(PART)"
