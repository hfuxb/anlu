cd D:/anlu/rtl/work/tmp/td_sign_chroma_20261010_production_r3/traffic_sign_td/td_project
import_device -package PH1P35MDG324 ph1_35p.db
open_project -single_run ./traffic_sign_td.al
elaborate -top design_top_wrapper
read_adc ../user_source/lab_ex_2026_nosoft/constraints_source/pin.adc
read_ip_adc -ip ddr2 -file ../user_source/ip_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc
optimize_rtl
read_sdc ./traffic_sign_td.sdc
read_sdc -ip ddr2 ../user_source/ip_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc
optimize_gate
legalize_phy_inst
read_sdc ./traffic_sign_td.sdc
read_sdc -ip ddr2 ../user_source/ip_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc
place
route
report_qor -step route -file route.qor
report_area -io_info -file route_area.rpt
update_timing -mode final
report_timing_summary -file route_timing.rpt
bitgen -bit traffic_sign_td.bit
close_project
exit
