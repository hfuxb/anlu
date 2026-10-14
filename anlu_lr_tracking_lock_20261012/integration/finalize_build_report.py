"""Record evidence for the just-built local artifact; refuse failing/stale runs."""
from pathlib import Path
import hashlib, json, re, shutil
from datetime import datetime, timezone

root=Path(__file__).resolve().parent.parent
out=root/'integration/td_bit'
bit=root/'fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_lr_tracking_lock.bit'
stages=(out/'stages_all.log').read_text(encoding='utf-8-sig')
assert 'CAR_BIT_BUILD_OK' in stages and 'CAR_BIT_TIMING_SIGNOFF_OK' in stages, 'TD build/signoff incomplete'
timing=(out/'traffic_sign_td_pr.timing').read_text(encoding='utf-8-sig')
status={k:float(re.search(k+r':\s*(-?[\d.]+)ns',timing)[1]) for k in ('SWNS','STNS','HWNS','HTNS')}
assert all(v>=0 for v in status.values()), status
assert 'Confidence          : Routed' in timing
assert bit.is_file() and bit.stat().st_size>0
assert bit.stat().st_mtime>=(out/'traffic_sign_td_pr.timing').stat().st_mtime
tests={
 'independent Gamma and bounded causal luma sharpening':root/'reports/tb_enhance.log',
 'automatic environment selection and complete-frame hysteresis':root/'reports/tb_environment.log',
 'complete720p 1800-sample environment statistics and frame path':root/'reports/tb_environment_full720.log',
 'KEY3 force-normal button debounce':root/'reports/tb_override.log',
 'reference L/R synthetic fog automatic routing and fresh recognition':root/'reports/tb_auto_recognition.log',
 'PATH N/D AUTO/LOCK exact HDMI glyphs (4 full720 frames)':root/'reports/tb_path_hdmi.log',
 'SIG-only detector and mode-exit result CDC':root/'sim/lr_turn/work_sig_only/run.log',
 'Sobel erosion opening and DDR packing':root/'reports/tb_morphology_opening_720p.log',
 'four-mode full720 stream alignment':root/'reports/tb_image_process_stream_96_full_720p.log',
 'direction hysteresis and 14-frame loss expiry (79 frames)':root/'sim/lr_turn/work_tracking/run.log',
 '12 reference-image scenarios':root/'sim/lr_turn/work/run.log',
 '1280x720 image frames':root/'sim/lr_turn/work_full720/run.log',
 'result metadata CDC (both edge phases)':root/'sim/lr_turn/work/tb_lr_metadata/run.log',
 'uniform Latin/digit font geometry':root/'sim/lr_turn/work/tb_osd_font/run.log',
 'HDMI 12 frames: six modes, SIG-only overlays and RGB alignment':root/'sim/lr_turn/work/tb_lr_hdmi/run.log',
 'KEY4 RAW ERO DIL MOT DEH SIG cycle, debounce and long press':root/'reports/tb_board_mode_selector_720p.log',
 'dehaze whole-image numeric reference and motion mask (14 frames)':root/'reports/tb_extra_modes.log',
 'motion full720 static/noise/reentry/truncated-frame recovery':root/'reports/tb_motion_full720.log',
 'actual ISP three-bit mode routing and pipeline alignment':root/'reports/tb_isp_modes.log',
 'acquisition/display latency 82 checks including actual DDR bank tags':root/'reports/tb_video_latency.log',
 'latency right-top exact glyphs and RGB alignment (7 full720 frames)':root/'reports/tb_latency_hdmi.log',
 'latency one-second display hold (3531 checks including 75000000 clocks)':root/'reports/tb_latency_display.log',
 'latency held OSD and RGB alignment (11 full720 frames)':root/'reports/tb_latency_hdmi_hold.log',
 'recognized L/R center coordinates and full720 label alignment':root/'reports/tb_coordinate_hdmi.log',
 'coordinate metadata epoch and actual LAT/status/Logo avoidance':root/'reports/tb_coordinate_latch.log',
 'STM32 UART':root/'reports/tb_car_uart.log',
 'car result CDC':root/'reports/tb_car_result_cdc.log',
 'action request/status pin UART transport':root/'sim/turn_closed_loop/work_transport/run.log',
 'acknowledged angle action decision (45 checks)':root/'reports/tb_action_decision.log',
 'complete dual-feedback car UART control (49 checks)':root/'reports/tb_action_control.log',
 'STM32 relative angle outer loop and plant':root/'reports/test_fpga_turn.log',
 'STM32 ISR mailbox and atomic status publication (792 checks)':root/'reports/test_fpga_owner.log',
 'checked physical gyro adapter (140 scenarios)':root/'reports/test_fpga_feedback.log',
}
for name,p in tests.items():
 text=p.read_text(encoding='utf-8-sig')
 assert 'PASS' in text and not re.search(r'(?m)^\s*(Fatal:|FAIL|ERROR:)',text),(name,p)
assert 'PASS LR tracking lock 79 frames' in (root/'sim/lr_turn/work_tracking/run.log').read_text(encoding='utf-8-sig'), '14-frame loss regression missing'
assert 'PASS SIG ONLY detector' in (root/'sim/lr_turn/work_sig_only/run.log').read_text(encoding='utf-8-sig'), 'SIG-only regression missing'
base=Path(r'D:\qrsfpga\qrsfpga\anlu_lr_turn_20261011')
base_manifest=json.loads((root/'integration/base_version_sha256.json').read_text(encoding='utf-8'))
for rel,expected in base_manifest.items():
 assert hashlib.sha256((base/rel).read_bytes()).hexdigest()==expected, ('Original version changed',rel)
expected={m[1]:chr(int(m[2],16)) for m in re.finditer(r'run_case\("\.\./([^"/]+)\.hex",8\'h([0-9a-f]+)\)',(root/'sim/lr_turn/cases.vh').read_text())}
sample_results={}
current=None
for line in (root/'sim/lr_turn/work/run.log').read_text().splitlines():
 m=re.match(r'CASE \.\./([^/]+)\.hex',line)
 if m:current=m[1]
 m=re.match(r'result (.) score=(\d+) L=(\d+) R=(\d+)',line)
 if m and current:sample_results[current]={'expected':expected[current],'direction':m[1],'match':int(m[2]),'left_iou':int(m[3]),'right_iou':int(m[4])}
assert len(sample_results)==12 and all(v['expected']==v['direction'] for v in sample_results.values())
sha=hashlib.sha256(bit.read_bytes()).hexdigest().upper()
area=(out/'traffic_sign_td_phy.area').read_text(encoding='utf-8-sig')
resources={}
for key in ('slice','eram','dsp'):
 m=re.search(r'(?m)^#'+re.escape(key)+r'\*?\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',area)
 if m: resources[key]={'used':int(m[1]),'available':int(m[2]),'percent':float(m[3])}
report={
 'generated_utc':datetime.now(timezone.utc).isoformat(),
 'project':'HX1P35A six image modes, AE/AWB, recognized center coordinates, one-second latency OSD and STM32 relative-angle turning',
 'bit':str(bit.relative_to(root)),'bytes':bit.stat().st_size,'sha256':sha,
 'final_routed_timing_ns':status,'resources':resources,
 'tests':{k:str(v.relative_to(root)) for k,v in tests.items()},
 'physical_camera_verified':False,
 'changed_in_this_build':['automatic_normal_dehaze_recognition','key3_force_normal','gamma_085_display','bounded_causal_luma_sharpen','complete_AL_source_list'],
 'automatic_dehaze_recognition_implemented':True,
 'key3_recognition_mode_lock_implemented':True,
 'reference_scene_results':sample_results,
 'base_version_preserved':True,
 'reference_templates':json.loads((root/'sim/lr_turn/reference_20261012/template_evidence.json').read_text(encoding='utf-8')),
 'lock_policy':{'confirm_frames':3,'hold_frames':14,'initial_score':50,'direction_margin':12,'switch_frames':6,'switch_score':65,'switch_margin':20},
 'recognition_mode':{'enabled_mode':'SIG (0)','disabled_modes':['RAW (3)','ERO (2)','DIL (1)','MOT (4)','DEH (5)'],'clear_lock_on_exit':True,'wait_for_complete_SOF_after_RAM_init':True,'visual_drive_stop_and_disarm_outside_SIG':True},
 'key4_cycle':['RAW','ERO','DIL','MOT','DEH','SIG'],
 'motion_detection':{'grid':[320,180],'threshold_luma':24,'highlight':'red 4x4 regions','first_frame_primes':True,'truncated_frame_invalidates':True,'camera_motion_or_exposure_changes_may_trigger':True},
 'dehaze':{'algorithm':'causal 3x3 group dark channel with fixed airlight and segmented reciprocal','airlight':240,'omega_q8':218,'minimum_transmission':64,'maximum_gain':2,'adaptive_airlight':False},
 'video_latency':{'start':'MIPI/CSI frame start','end':'same DDR frame first HDMI active pixel','resolution_ms':0.1,'position':'top right','invalid':'----.-','overflow_ms':9999.9,'camera_exposure_and_screen_internal_latency_included':False,'full_frame_tag_required':True,'measurement_every_frame':True,'display_refresh_ms':1000,'display_value':'latest complete measurement, held between updates; not averaged','first_fault_and_recovery_immediate':True,'no_measurement_timeout_ms':1500},
 'coordinate_label':{'enabled':'SIG, valid box, accepted L or R','point':'floor((xmin+xmax)/2), floor((ymin+ymax)/2)','units':'1280x720 image pixels, origin top left','format':'L (0640,0360)','font_cell':[16,16],'label_size':[208,20],'frame_latched':True,'unrecognized_hidden':True,'screen_edge_clamped':True,'existing_osd_avoided':True,'held_target_uses_retained_box':True},
 'extra_stream_delay_clocks':20,
 'morphology':{'erosion':'erosion(Sobel)','dilation':'dilation(erosion(Sobel))','stream_latency_clocks':4,'standard_sobel_gx_fixed':True},
 'source_sha256':{},
 'automatic_recognition':{'statistics_source':'AWB, before dehaze','sample_points_per_720p_frame':1800,'histogram_bins':16,'trim_each_tail':'1/32','enter_max_bin_span':5,'enter_min_mean_dark':48,'enter_max_mean_chroma_range':40,'enter_ms':500,'enter_min_frames':8,'exit_min_bin_span':8,'exit_min_mean_chroma_range':56,'exit_max_mean_dark':32,'exit_ms':1000,'exit_min_frames':16,'minimum_hold_ms':2000,'CSI_clock_hz':60000000,'frame_latched':True,'partial_frame_reject':True,'long_SOF_gap_reset_ms':250,'heuristic_not_physical_fog_measurement':True,'detector_shared':True,'held_match_used_for_switching':False},
 'display_enhancement':{'enabled':['DEH','SIG automatic dehaze'],'gamma':0.85,'luma':'(R+2G+B)/4','gamma_apply':'same delta to RGB, saturate','sharpen':'causal 2x2 luma unsharp mask','deadband':4,'strength':'1/4 above deadband','max_correction':4,'latency_stages':7,'recognition_uses_enhanced_pixels':False,'additional_DSP_required':False},
 'KEY3':{'pin':'B9','action':'toggle AUTO/force normal','debounce_ms':20,'commit':'next valid SOF','reset_default':'AUTO','legacy_obstacle_simulation_removed':True},
}
verification=json.loads((root/'stm32/verification.json').read_text(encoding='utf-8'))
assert verification['status'].startswith('PASS')
hex_path=root/'stm32/WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex'
assert hashlib.sha256(hex_path.read_bytes()).hexdigest()==verification['hex_sha256']
report['stm32_hex']={'path':str(hex_path.relative_to(root)),'bytes':hex_path.stat().st_size,
 'sha256':verification['hex_sha256'].upper(),'flash_start':'0x08000000',
 'target':'4WD_Car','hardware_tested':False}
report['turn_control']={'request_mode':16,'target_cdeg':9000,'max_rate_mrad_s':700,
 'forward_mm_s':0,'feedback':'checked calibrated physical IMU gyro Z integrated at 100 Hz',
 'angle_tolerance_cdeg':150,'settle_ms':200,'stm32_timeout_ms':7000,
 'stm32_keepalive_ms':300,'fpga_timeout_ms':8000,'matching_ack_and_heartbeat_ms':500,
 'completion':'matching ACCEPTED/RUNNING then matching DONE, never fixed-duration',
 'trigger':'three stabilized recognition events; no junction-distance detection',
 'wheel_encoder_PI_preserved':True,'mandatory_paired_firmware':True}
compressed=bit.with_name(bit.stem+'_compress.bit')
assert compressed.is_file() and compressed.stat().st_mtime>=(out/'traffic_sign_td_pr.timing').stat().st_mtime
report['compressed_bit']={'path':str(compressed.relative_to(root)),'bytes':compressed.stat().st_size,'sha256':hashlib.sha256(compressed.read_bytes()).hexdigest().upper(),'same_design':True}
for p in (root/'fpga/traffic_sign_td/user_source').rglob('*.v'):
 report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (root/'rtl').glob('*.v'):
 report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (root/'stm32/WHEELTEC_C50X_FPGA_PD89/BALANCE').rglob('*'):
 if p.suffix.lower() in ('.c','.h'):
  report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
(root/'构建结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 六档图像处理、延迟显示与 STM32 角度转向构建结果','',f'- bit：`{report["bit"]}`',f'- 大小：{report["bytes"]} 字节',
 f'- SHA-256：`{sha}`','',f'最终布线时序：Setup WNS **+{status["SWNS"]:.3f} ns**、Hold WNS **+{status["HWNS"]:.3f} ns**，Setup/Hold TNS 均为 0。',
 '', '资源：']
for k,v in resources.items(): lines.append(f'- {k}：{v["used"]}/{v["available"]}（{v["percent"]:.2f}%）')
lines+=['',f'- 配套 STM32 HEX：`{report["stm32_hex"]["path"]}`（4WD_Car / 0x08000000）',
 f'- HEX SHA-256：`{report["stm32_hex"]["sha256"]}`',
 '本版需要一起升级 FPGA bit 与 STM32 HEX；旧固件没有动作状态心跳，FPGA 不允许 ARM。',
 '转向改为 STM32 根据校准后的实测陀螺仪角速度积分执行相对 ±90°、最大0.7 rad/s 的原地转向，保留编码器轮速 PI。FPGA 发带序号的角度请求，必须先收到该序号 ACCEPTED/RUNNING、再收到 DONE 才结束；连续匹配反馈丢失500ms或总时长8s则停车并撤销 ARM。STM32 保活丢失300ms、角度反馈无效、使能关闭或执行超过7s时归零。',
 '控制器仿真不等于实车角度验证；上电需静止约13秒完成原启动等待及陀螺仪校准，实车先验证陀螺仪左右符号和最终角度。转向触发仍为稳定识别三次，未新增路口距离判定。详细协议与操作见 `stm32/闭环转向说明.md`。']
lines+=['','KEY4：RAW → ERO → DIL → MOT → DEH → SIG → RAW，识别放在最后。MOT 标红相邻帧变化区域，进入后的第一帧建立参考；DEH 为固定大气光的轻量暗通道去雾。只有 SIG 识别并允许视觉小车控制，其余模式退出锁定、停车并撤销 ARM。',
 '所有画面右上角LAT每帧测量MIPI/CSI帧首到同DDR帧首个HDMI有效像素的延迟，分辨率0.1ms；健康数字约每1秒在帧首发布最近完整值，期间保持，不平均。首次有效/invalid/OVFL/恢复即时发布，1.5秒无测量更新失效。不包含曝光和屏幕内部延迟；无有效标签显示----.-，超出9999.9ms显示OVFL。',
 'SIG内只有确认L/R且框有效才在框上方显示中心像素坐标（如L (0640,0360)）；候选?、WAIT、无框和非SIG均隐藏。坐标与框/方向按同帧锁存，统一16×16字体，横向裁切及Logo/状态/LAT避让，靠顶部放框内；低分保持时使用保留框位置。SIG新增自动正常/去雾识别和KEY3强制正常；PATH显示N/D与AUTO/LOCK。见docs/自动去雾识别与增强.md。',
 '', '新增模块在所有模式增加相同的20拍额外视频流延迟（比此前多7拍），不改变像素顺序、DDR布局和HDMI读取时序。运动检测不是障碍距离测量，固定摄像头并等待曝光稳定后演示。去雾使用固定参数，无雾场景也可能变暗或饱和。',
 '','正式标识构造场景（RTL 仿真，非实物准确率）：','', '| 场景 | 期望/输出 | MATCH |','|---|---|---|']
for name,result in sample_results.items(): lines.append(f'| {name} | {result["expected"]}/{result["direction"]} | {result["match"]} |')
lines+=['','已通过的测试：']+[f'- {k}（日志：`{v.relative_to(root)}`）' for k,v in tests.items()]
lines+=['','参考图合成场景不是实物准确率测试；摄像头、纸质牌和不同照明的效果待上板验证。',
 '', '只有 SIG 识别并显示框、DIR、MATCH；其他模式关闭检测并清除旧结果。重新进入从新完整帧确认；退出 SIG 小车停车并撤销 armed，重入需要手动 ARM。初次三帧确认方向；低分保持；反向六帧连续 MATCH≥65、差值≥20 后同步改向；前十三帧丢失保留，连续丢失第十四帧清除（当前相机配置约0.235秒）。DIL 改为 Sobel→腐蚀→膨胀，RGB/灰度/标记统一四拍延迟；标准 Sobel 水平梯度误用的中间像素已纠正。原版本源文件和 bit 的 SHA-256 均已核对保持一致。\n\n自动曝光、白平衡沿用原版；新增正常/去雾识别自动选择及显示专用Gamma/限幅锐化；SIG 使能同步到小车系统域并接入现有 STOP 条件，左右箭头模板已按两张正式标识分别提取；状态字母和数字已统一字号；Logo 地址预计算避免乘法与 ROM 查表落在同一显示时钟周期。','']
(root/'构建结果.md').write_text('\n'.join(lines),encoding='utf-8')
# Replace inherited template reports at compatibility paths with CURRENT data.
shutil.copy2(out/'traffic_sign_td_pr.timing',root/'integration/traffic_sign_td_pr.timing')
shutil.copy2(out/'traffic_sign_td_pr.timing',root/'fpga/traffic_sign_td/td_project/final_timing.rpt')
for name in ('route_flow.status','bitgen_param.txt'):
 shutil.copy2(out/name,root/'integration'/name)
print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'},ensure_ascii=False,indent=2))
