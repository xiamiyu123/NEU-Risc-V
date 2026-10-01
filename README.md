# 课程设计 CPU

本仓库实现五级流水线的 RV32I CPU，覆盖 40 条标准 RV32I 指令，并保留课程设计的定制指令 `uadd8sat`。设计依据和路线图见 [DESIGN_ROADMAP.md](DESIGN_ROADMAP.md)。

## 运行验证

需要 Icarus Verilog；可选 Yosys 检查可综合性。macOS 上可用 `brew install icarus-verilog yosys` 安装。

```sh
make test
make synth-check
make synth-xilinx
```

`make test` 运行流水线自检、ROM 演示和 RV32I 指令及异常测试，覆盖转发优先级、load-use 停顿、`x0`、分支冲刷、字节/半字访存和定制指令。`make synth-check` 做通用综合，`make synth-xilinx` 做 Xilinx 7 系列映射；日志位于忽略跟踪的 `build/`。

## 结构与接口

- `rtl/rv32_core.v`：IF/ID/EX/MEM/WB 流水线、译码、转发、阻塞与冲刷。
- `rtl/rv32_sync_mem.v`：同步读、按字节写的 32 位字存储器，可用 `$readmemh` 初始化。
- `rtl/rv32_soc.v`：内核加分离的指令/数据存储器，默认每块 256 字。
- `tb/`：独立的自检和 ROM 初始化演示。

PC 复位值为 0，地址按字节计。支持 RV32I 的整数运算、分支与跳转、`lb`/`lbu`/`lh`/`lhu`/`lw`、`sb`/`sh`/`sw`、`fence`、`ecall` 和 `ebreak`。单核、顺序、无缓存的存储器接口使 `fence` 无需额外硬件操作。`ecall` 和 `ebreak` 向外部环境报告异常。

| 类别 | 指令 |
| --- | --- |
| 寄存器运算 | `add` `sub` `sll` `slt` `sltu` `xor` `srl` `sra` `or` `and` |
| 立即数运算 | `addi` `slti` `sltiu` `xori` `ori` `andi` `slli` `srli` `srai` |
| 加载与存储 | `lb` `lh` `lw` `lbu` `lhu` `sb` `sh` `sw` |
| 分支 | `beq` `bne` `blt` `bge` `bltu` `bgeu` |
| 上位立即数与跳转 | `lui` `auipc` `jal` `jalr` |
| 内存顺序与环境 | `fence` `ecall` `ebreak` |

指令与数据存储器分离，默认各 256 个字，即各 1 KiB。配置范围之外的取指或数据访问会报告访问故障，不会按低位回绕；对齐不满足要求的跳转、半字或字访存会报告地址未对齐。异常接口由 `fault`、`fault_cause`、`fault_pc` 和 `fault_tval` 构成：先让更早的指令完成，再置位 `fault` 并停机；故障指令及其后续指令不产生副作用。`fault_cause` 使用 RISC-V 常见编码：0/1/2 为取指未对齐/访问故障/非法指令，3 为断点，4/5 为加载未对齐/访问故障，6/7 为存储未对齐/访问故障，11 为机器模式环境调用。未实现特权级、CSR 或异常入口；运行环境可用这些端口处理终止事件。

本设计只实现 RV32I 基础整数指令集，`Zicsr`、`Zifencei`、压缩指令及乘除法扩展均不在范围内。存储器容量和异常处理方式是这个 SoC 的运行环境约定；运行大型软件仍需扩展存储器及系统接口。

演示程序相当于：

```asm
lui       x1, 0x10203
ori       x1, x1, 0x0fa
lui       x2, 0x01020
ori       x2, x2, 0x414
uadd8sat  x3, x1, x2
sw        x3, 0(x0)
jal       x0, 0
```

定制指令 `uadd8sat` 使用 `custom-0` opcode `0001011`、R 型字段、`funct3=000`、`funct7=0000000`。它对两个源寄存器内的四对无符号字节分别求和并饱和到 255。演示结果为 `0x112234ff`，写入数据存储器字 0；`rv32_soc` 的 `result_valid` 和 `result_data` 保留这次写入，方便之后接板级观察逻辑。它不是标准汇编器内建的助记符，`program/demo.hex` 已提供机器码。

## 板级状态

RTL 已通过本地仿真和 Yosys 通用综合检查，也通过 Yosys 的 Xilinx 7 系列映射检查。尚无具体开发板型号、引脚约束和 Vivado 环境，因此没有声称完成时序收敛或实板运行。拿到板卡资料后，需要在 Vivado 中添加顶层引脚和时钟约束、装入 `program/demo.hex`，再以板上可用的输出或调试接口验证 `result_data`。
