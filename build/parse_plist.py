import plistlib, zipfile, sys
z = zipfile.ZipFile(r"C:\Users\fanyo\Desktop\TrollLifeAI.ipa")
d = plistlib.loads(z.read("Payload/TrollLifeApp.app/Info.plist"))
keys = ["CFBundleIdentifier","CFBundleExecutable","CFBundleDisplayName","CFBundleName",
        "CFBundleShortVersionString","CFBundleVersion","LSMinimumSystemVersion","MinimumOSVersion",
        "UIDeviceFamily","UIRequiredDeviceCapabilities","UIFileSharingEnabled","LSSupportsOpeningDocumentsInPlace",
        "DTPlatformName","DTXcode"]
for k in keys:
    if k in d: print(f"  {k:<34} = {d[k]}")
print(f"  {'NSAppTransportSecurity':<34} = {d.get('NSAppTransportSecurity')}")
print(f"  {'UISupportedInterfaceOrientations':<34} = {d.get('UISupportedInterfaceOrientations')}")
print(f"  {'UILaunchScreen':<34} = {d.get('UILaunchScreen')}")
print(f"  {'CFBundleIcons.PrimaryIcon.Files':<34} = {d.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon',{}).get('CFBundleIconFiles')}")
