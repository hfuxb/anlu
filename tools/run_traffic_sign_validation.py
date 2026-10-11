"""运行隔离的 XSim 回归，保留日志，不覆盖已有报告。"""
import argparse
import json
import subprocess
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(r"D:/Xilinx/Vivado/2019.2/bin")
SOURCE = ROOT / "fpga/traffic_sign_td/user_source"


def run_step(directory, name, args):
    with (directory / f"{name}_console.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(["rtk", "proxy", "cmd", "/c", str(BIN / f"{name}.bat"), *args],
                                cwd=directory, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        text = (directory / f"{name}_console.log").read_text(encoding="utf-8", errors="replace")
        raise RuntimeError(f"{name} 返回 {result.returncode}: " + text[-1800:])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--tests", nargs="+", required=True)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--characterize", action="store_true")
    parser.add_argument("--rtl")
    args = parser.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=False)
    detector = str(Path(args.rtl).resolve()) if args.rtl else str(SOURCE / "image/traffic_sign/traffic_sign_detector_96.v")
    hdl = SOURCE / "lab_ex_2026_nosoft/hdl_source"
    sources = {
        "tb_traffic_sign_detector_96": [detector],
        "tb_traffic_sign_photo_replay": [detector],
        "tb_traffic_sign_joint_replay": [detector],
        "tb_traffic_sign_joint_evidence": [detector],
        "tb_traffic_sign_result_cdc": [str(SOURCE / "image/traffic_sign/traffic_sign_result_cdc.v")],
        "tb_osd_question": [str(hdl / "osd_char_lib.v")],
        "tb_hdmi_720p": [str(hdl / f) for f in ["vtc/uivtc.v", "hdmi_mixer.v", "anlogic_logo_rom.v", "osd_char_lib.v"]],
        "tb_hdmi_black_camera": [str(hdl / f) for f in ["vtc/uivtc.v", "hdmi_mixer.v", "anlogic_logo_rom.v", "osd_char_lib.v"]],
    }
    summary = []
    for test in args.tests:
        directory = out / test
        directory.mkdir()
        if test in ["tb_traffic_sign_joint_replay", "tb_traffic_sign_photo_replay"]:
            for fixture in (ROOT / "sim/video720/fixtures").glob("*.mem"):
                shutil.copyfile(fixture, directory / fixture.name)
        compile_args = [*sources[test], "--sv", str(ROOT / f"sim/video720/{test}.sv"), "-log", "compile.log"]
        if test == "tb_traffic_sign_joint_replay" and not args.baseline:
            compile_args += ["-d", "JOINT_FEATURES"]
        run_step(directory, "xvlog", compile_args)
        elaborate = [test, "-s", "snapshot", "-log", "elaborate.log"]
        if test == "tb_traffic_sign_joint_replay" and not args.baseline:
            elaborate += ["-debug", "all"]
        run_step(directory, "xelab", elaborate)
        simulation = ["snapshot", "-runall", "-log", "run.log"]
        if test == "tb_traffic_sign_joint_replay" and not args.baseline:
            simulation = ["snapshot", "--tclbatch", (ROOT / "sim/video720/joint_wave.tcl").as_posix(), "-log", "run.log"]
        if args.baseline:
            simulation += ["--testplusarg", "BASELINE"]
        if args.characterize:
            simulation += ["--testplusarg", "CHARACTERIZE"]
        run_step(directory, "xsim", simulation)
        lines = (directory / "run.log").read_text(encoding="utf-8", errors="replace").splitlines()
        markers = [line for line in lines if line.startswith(("PASS", "SUMMARY", "BASELINE"))]
        failures = [line for line in lines if line.lstrip().startswith(("Fatal:", "ERROR:", "FAIL"))]
        passed = bool(markers) and not failures
        entry = {"test": test, "passed": passed, "markers": markers, "failures": failures[:4]}
        summary.append(entry)
        print(json.dumps(entry, ensure_ascii=False), flush=True)
        (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        if not passed:
            raise RuntimeError(f"{test} 失败，日志: {directory / 'run.log'}")


if __name__ == "__main__":
    main()
