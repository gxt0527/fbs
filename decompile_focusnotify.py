import zipfile

path = r'C:\Users\taoxg\.gradle\caches\9.1.0\transforms\22ca7a1a32793000b84dc6645911d792\workspace\transformed\HyperFocusApi-2.0\jars\classes.jar'

z = zipfile.ZipFile(path)
targets = [
    'com/hyperfocus/api/FocusNotifyApi.class',
    'com/hyperfocus/api/FocusNotifyApi$FocusDiy.class',
    'com/hyperfocus/api/ExampleApi.class',
    'com/hyperfocus/api/info/ActionInfo.class',
]

for cls_name in targets:
    if cls_name not in z.namelist():
        continue
    with z.open(cls_name) as f:
        data = f.read()
    readable = ''.join(chr(b) if 32 <= b < 127 else '\n' for b in data)
    lines = [l.strip() for l in readable.split('\n') if l.strip() and len(l.strip()) > 3]
    print(f"\n=== {cls_name} ===")
    seen = set()
    for l in lines[:80]:
        if l not in seen:
            print(f"  {l}")
            seen.add(l)
