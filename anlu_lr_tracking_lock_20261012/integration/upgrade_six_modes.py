from pathlib import Path

root=Path(__file__).resolve().parent.parent
hdl=root/'fpga/traffic_sign_td/user_source/lab_ex_2026_nosoft/hdl_source'
def edit(path,replacements):
    s=path.read_text(encoding='utf-8-sig')
    for old,new in replacements:
        assert old in s,(path,old)
        s=s.replace(old,new)
    path.write_text(s,encoding='utf-8')
edit(hdl/'design_top_wrapper.v',[
 ('[1:0]\t\tS_algo_mode','[2:0]\t\tS_algo_mode'),
 ("S_algo_mode_24m==2'b00","S_algo_mode_24m==3'd0"),
 ("S_algo_mode_sync_1 <= 2'b11","S_algo_mode_sync_1 <= 3'd3"),
 ("S_algo_mode_sync_2 <= 2'b11","S_algo_mode_sync_2 <= 3'd3")])
edit(hdl/'hdmi_mixer.v',[
 ('input wire [1:0]  I_image_mode','input wire [2:0]  I_image_mode'),
 ('reg [1:0]  S_image_mode','reg [2:0]  S_image_mode'),
 ("S_image_mode_sync2==2'b00","S_image_mode_sync2==3'd0"),
 ("S_image_mode_frame==2'b00","S_image_mode_frame==3'd0"),
 ("S_image_mode_sync1 <= 2'b11","S_image_mode_sync1 <= 3'd3"),
 ("S_image_mode_sync2 <= 2'b11","S_image_mode_sync2 <= 3'd3"),
 ("S_image_mode_frame <= 2'b11","S_image_mode_frame <= 3'd3"),
 ("2'b11: begin // RAW","3'd3: begin // RAW"),
 ("2'b10: begin // ERO","3'd2: begin // ERO"),
 ("2'b01: begin // DIL","3'd1: begin // DIL"),
 ('default: begin // SIG', '''3'd4: begin // MOT
                                if(S_dyn_x < 12'd96) S_pf_char = "M";
                                else if(S_dyn_x < 12'd112) S_pf_char = "O";
                                else S_pf_char = "T";
                            end
                            3'd5: begin // DEH
                                if(S_dyn_x < 12'd96) S_pf_char = "D";
                                else if(S_dyn_x < 12'd112) S_pf_char = "E";
                                else S_pf_char = "H";
                            end
                            default: begin // SIG''')])
al=root/'fpga/traffic_sign_td/td_project/traffic_sign_td.al'
s=al.read_text(encoding='utf-8-sig')
for name in ('dehaze_stream_96','motion_stream_96','image_extra_modes_96'):
    rel=f'../user_source/image/stream/{name}.v'
    assert rel not in s
    entry=f'''            <File Path="{rel}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
'''
    s=s.replace('        <Verilog>\n','        <Verilog>\n'+entry,1)
al.write_text(s,encoding='utf-8')
edit(root/'sim/video720/tb_board_mode_selector.sv',[
 ('wire [1:0] mode','wire [2:0] mode'),
 ('task check(input [1:0] expected)','task check(input [2:0] expected)'),
 ("tap(); check(2'b00);", "tap(); check(3'd4);\n    tap(); check(3'd5);\n    tap(); check(3'd0);"),
 ('// long hold must not switch the image','// long hold must not switch the image\n    key_n=0; repeat(2) @(negedge clk);\n    key_n=1; repeat(12) @(negedge clk); check(3\'d3); // debounce rejects bounce'),
 ('PASS BOARD KEY4 MODE SELECTOR','PASS BOARD KEY4 MODE SELECTOR RAW ERO DIL MOT DEH SIG')])
print('Six modes integrated; SIG is last; full-width comparisons protect recognition.')
