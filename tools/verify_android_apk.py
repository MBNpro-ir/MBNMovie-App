"""Check the packaged manifest, not only Gradle's requested minimum."""
import argparse
import os
import pathlib
import subprocess
import xml.etree.ElementTree as ET
import re

parser = argparse.ArgumentParser()
parser.add_argument("apks", nargs="+")
args = parser.parse_args()
sdk = pathlib.Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
analyzer = sdk / "cmdline-tools/latest/bin" / ("apkanalyzer.bat" if os.name == "nt" else "apkanalyzer")
ns = "{http://schemas.android.com/apk/res/android}"
for apk in args.apks:
    xml = subprocess.check_output([str(analyzer), "manifest", "print", apk], text=True)
    root = ET.fromstring(xml)
    minimum = int(root.find("uses-sdk").get(ns + "minSdkVersion"))
    assert minimum == 23, f"{apk}: packaged minimum is {minimum}, expected Android 6/API 23"
    spec = (pathlib.Path(__file__).resolve().parents[1] / "pubspec.yaml").read_text(encoding="utf-8")
    expected_code = 2000 + int(re.search(r"^version:.*\+(\d+)", spec, re.M)[1])
    assert int(root.get(ns + "versionCode")) == expected_code, f"{apk}: upgrade versionCode mismatch"
    features = {item.get(ns + "name"): item.get(ns + "required") for item in root.findall("uses-feature")}
    for name in ("android.hardware.touchscreen", "android.hardware.faketouch",
                 "android.hardware.sensor.accelerometer", "android.software.leanback"):
        assert features.get(name) == "false", f"{apk}: {name} must be optional"
    app = root.find("application")
    assert app.get(ns + "name", "").endswith(".MbnApplication"), f"{apk}: legacy HTTPS initialization missing"
    assert app.get(ns + "banner"), f"{apk}: TV banner missing"
    assert any(item.get(ns + "name") == "android.intent.category.LEANBACK_LAUNCHER"
               for item in app.iter("category")), f"{apk}: TV launcher missing"
    print(f"{pathlib.Path(apk).name}: API 23 minimum and TV manifest verified")
