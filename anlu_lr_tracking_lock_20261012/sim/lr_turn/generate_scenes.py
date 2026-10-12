from pathlib import Path
import runpy
here=Path(__file__).resolve().parent
runpy.run_path(str(here/'prepare_reference_signs.py'),run_name='__main__')
runpy.run_path(str(here/'generate_tracking_scenes.py'),run_name='__main__')
