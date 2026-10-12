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
 'tracking lock and persistent loss (29 frames)':root/'sim/lr_turn/work_tracking/run.log',
 '12 reference-image scenarios':root/'sim/lr_turn/work/run.log',
 '1280x720 image frames':root/'sim/lr_turn/work_full720/run.log',
 'result metadata CDC (both edge phases)':root/'sim/lr_turn/work/tb_lr_metadata/run.log',
 'uniform Latin/digit font geometry':root/'sim/lr_turn/work/tb_osd_font/run.log',
 'HDMI alignment, ROI, score, frame latch':root/'sim/lr_turn/work/tb_lr_hdmi/run.log',
 'STM32 UART':root/'reports/tb_car_uart.log',
 'car policy':root/'reports/tb_car_decision.log',
 'car result CDC':root/'reports/tb_car_result_cdc.log',
 'complete car control':root/'reports/tb_car_control.log',
}
for name,p in tests.items():
 text=p.read_text(encoding='utf-8-sig')
 assert 'PASS' in text and not re.search(r'(?m)^\s*(Fatal:|FAIL|ERROR:)',text),(name,p)
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
for key in ('slice*','eram','dsp'):
 m=re.search(r'(?m)^#'+re.escape(key)+r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',area)
 if m: resources[key]={'used':int(m[1]),'available':int(m[2]),'percent':float(m[3])}
report={
 'generated_utc':datetime.now(timezone.utc).isoformat(),
 'project':'HX1P35A associated-target tracking and confirmed L/R lock with AE/AWB',
 'bit':str(bit.relative_to(root)),'bytes':bit.stat().st_size,'sha256':sha,
 'final_routed_timing_ns':status,'resources':resources,
 'tests':{k:str(v.relative_to(root)) for k,v in tests.items()},
 'physical_camera_verified':False,
 'reference_scene_results':sample_results,
 'base_version_preserved':True,
 'reference_templates':json.loads((root/'sim/lr_turn/reference_20261012/template_evidence.json').read_text(encoding='utf-8')),
 'lock_policy':{'confirm_frames':3,'hold_frames':8,'initial_score':50,'direction_margin':12},
 'source_sha256':{},
}
for p in (root/'fpga/traffic_sign_td/user_source').rglob('*.v'):
 report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (root/'rtl').glob('*.v'):
 report['source_sha256'][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
(root/'构建结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 左右转目标跟踪与方向锁定版构建结果','',f'- bit：`{report["bit"]}`',f'- 大小：{report["bytes"]} 字节',
 f'- SHA-256：`{sha}`','',f'最终布线时序：Setup WNS **+{status["SWNS"]:.3f} ns**、Hold WNS **+{status["HWNS"]:.3f} ns**，Setup/Hold TNS 均为 0。',
 '', '资源：']
for k,v in resources.items(): lines.append(f'- {k}：{v["used"]}/{v["available"]}（{v["percent"]:.2f}%）')
lines+=['','正式标识构造场景（RTL 仿真，非实物准确率）：','', '| 场景 | 期望/输出 | MATCH |','|---|---|---|']
for name,result in sample_results.items(): lines.append(f'| {name} | {result["expected"]}/{result["direction"]} | {result["match"]} |')
lines+=['','已通过的测试：']+[f'- {k}（日志：`{v.relative_to(root)}`）' for k,v in tests.items()]
lines+=['','参考图合成场景不是实物准确率测试；摄像头、纸质牌和不同照明的效果待上板验证。',
 '', '确认三帧后锁定方向；0 分仍保持；连续丢失第八帧清除并重新确认。原版本源文件和 bit 的 SHA-256 均已核对保持一致。\n\n自动曝光、白平衡、按键选择和小车控制核心沿用原版，左右箭头模板已按两张正式标识分别提取；状态字母和数字已统一字号；Logo 地址预计算避免乘法与 ROM 查表落在同一显示时钟周期。','']
(root/'构建结果.md').write_text('\n'.join(lines),encoding='utf-8')
# Replace inherited template reports at compatibility paths with CURRENT data.
shutil.copy2(out/'traffic_sign_td_pr.timing',root/'integration/traffic_sign_td_pr.timing')
shutil.copy2(out/'traffic_sign_td_pr.timing',root/'fpga/traffic_sign_td/td_project/final_timing.rpt')
for name in ('route_flow.status','bitgen_param.txt'):
 shutil.copy2(out/name,root/'integration'/name)
print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'},ensure_ascii=False,indent=2))
