"""Audit the fixed allowed patch set against the retained vendor tree."""
from pathlib import Path
import hashlib,json

here=Path(__file__).resolve().parent
p=here/'patch_manifest.json'
manifest=json.loads(p.read_text(encoding='utf-8'))
source=Path(manifest['source'])
copy=here/'WHEELTEC_C50X_FPGA_PD89'
for item in manifest['changes']:
    assert hashlib.sha256((source/item['path']).read_bytes()).hexdigest()==item['original_sha256']
allowed={'HARDWARE/Inc/uartx.h','SYSTEM/sys/sys.c','BALANCE/balance_task.c',
 'BALANCE/Inc/balance_task.h','BALANCE/data_task.c','BALANCE/uartx_callback.c',
 'BALANCE/imu_task.c','USER/WHEELTEC.uvprojx'}
changes=[]
for before in source.rglob('*'):
    if not before.is_file() or before.suffix.lower() not in {'.c','.h','.s','.uvprojx'}:continue
    rel=before.relative_to(source).as_posix()
    after=copy/rel
    assert after.exists(),rel
    if before.read_bytes()!=after.read_bytes():
        assert rel in allowed,('Unexpected vendor patch',rel)
        changes.append({'path':rel,'original_sha256':hashlib.sha256(before.read_bytes()).hexdigest(),
          'patched_sha256':hashlib.sha256(after.read_bytes()).hexdigest()})
assert {c['path'] for c in changes}==allowed
added=['BALANCE/fpga_turn.c','BALANCE/fpga_turn_feedback.c',
 'BALANCE/Inc/fpga_turn.h','BALANCE/Inc/fpga_turn_feedback.h']
manifest['copy']=str(copy)
manifest['changes']=changes
manifest['added_files']={rel:hashlib.sha256((copy/rel).read_bytes()).hexdigest() for rel in added}
manifest['purpose']='USART3 angle-action controller with physical yaw feedback; original wheel encoder PI preserved'
p.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS allowed vendor patch set: 8 edited and 4 added files')
