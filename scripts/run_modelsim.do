# 在 ModelSim/Questa 的 Transcript 中执行：do /仓库路径/scripts/run_modelsim.do
# 修改 testbench 可选择其他测试台；本脚本尚未经实际 ModelSim 验证。
set testbench tb_rv32_soc
set root_dir [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir [file join $root_dir neu_risc_v.srcs sources_1 rtl]
set tb_dir [file join $root_dir neu_risc_v.srcs sim_1 tb]
set run_dir [file join $root_dir build modelsim]

file mkdir $run_dir
cd $run_dir
vlib work
vmap work work
vlog -sv "+incdir+$rtl_dir" "+incdir+$tb_dir" \
    {*}[glob [file join $rtl_dir *.v]] \
    {*}[glob [file join $tb_dir *.sv]] \
    {*}[glob [file join $root_dir review tb_review*.sv]]
file copy -force [file join $root_dir neu_risc_v.srcs sources_1 mem demo.mem] demo.mem
vsim -voptargs=+acc work.$testbench
log -r /*
add wave -r sim:/$testbench/*
run -all
wave zoom full
