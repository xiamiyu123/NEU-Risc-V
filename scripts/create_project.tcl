# Usage: vivado -mode batch -source scripts/create_project.tcl -tclargs <part>
if {$argc != 1} {
    error "Usage: create_project.tcl <part>"
}

set root_dir [file normalize [file join [file dirname [info script]] ..]]
set src_dir [file join $root_dir neu_risc_v.srcs]
set project_dir [file join $root_dir build vivado]

create_project neu_risc_v $project_dir -part [lindex $argv 0]
set_property target_language Verilog [current_project]
set_property target_simulator XSim [current_project]

add_files -fileset sources_1 -norecurse [glob [file join $src_dir sources_1 rtl *.v]]
add_files -fileset sources_1 -norecurse [file join $src_dir sources_1 mem demo.mem]
set_property top rv32_soc [get_filesets sources_1]
set_property generic {IMEM_FILE="demo.mem"} [get_filesets sources_1]

set tb_dir [file join $src_dir sim_1 tb]
add_files -fileset sim_1 -norecurse [glob [file join $tb_dir *.sv] [file join $tb_dir *.svh]]
set_property include_dirs [list $tb_dir] [get_filesets sim_1]
set_property top tb_rv32_soc [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]

set constraints [glob -nocomplain [file join $src_dir constrs_1 *.xdc]]
if {[llength $constraints]} {
    add_files -fileset constrs_1 -norecurse $constraints
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created: [file join $project_dir neu_risc_v.xpr]"
