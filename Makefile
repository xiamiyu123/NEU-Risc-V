IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
RTL := rtl/rv32_core.v rtl/rv32_sync_mem.v rtl/rv32_soc.v

.PHONY: test synth-check synth-xilinx
test:
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -I tb -s tb_rv32_soc -o build/tb_rv32_soc $(RTL) tb/tb_rv32_soc.sv
	$(VVP) build/tb_rv32_soc
	$(IVERILOG) -g2012 -Wall -I tb -s tb_demo -o build/tb_demo $(RTL) tb/tb_demo.sv
	$(VVP) build/tb_demo
	$(IVERILOG) -g2012 -Wall -I tb -s tb_rv32i -o build/tb_rv32i $(RTL) tb/tb_rv32i.sv
	$(VVP) build/tb_rv32i

synth-check:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv $(RTL); hierarchy -check -top rv32_soc; synth -top rv32_soc; check -assert' > build/yosys.log

synth-xilinx:
	mkdir -p build
	$(YOSYS) -Q -T -p 'read_verilog -sv $(RTL); synth_xilinx -top rv32_soc -family xc7; check -assert' > build/yosys-xilinx.log
