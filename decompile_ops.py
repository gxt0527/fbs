import sys, logging
logging.disable(logging.CRITICAL)
sys.path.insert(0, r'C:/Users/taoxg/.workbuddy/binaries/python/envs/androguard/Lib/site-packages')
from androguard.core.dex import DEX

with open(r'E:/MSRR/fbs/tmp_pronto/si_extracted/classes3.dex', 'rb') as f:
    d = DEX(f.read())

# Find XiaomiOpsService methods and key strings
for cls in d.get_classes():
    cls_name = cls.get_name()
    if 'XiaomiOpsService' in cls_name or 'checkShizukuAndFire' in cls_name:
        print(f"\n=== {cls_name} ===")
        for method in cls.get_methods():
            m = method.get_name()
            code = method.get_code()
            if code is None: continue
            bc = code.get_bc()
            strings = []
            for ins in bc.get_instructions():
                out = ins.get_output()
                name = ins.get_name()
                if name in ['const-string', 'const-string/jumbo']:
                    s = out.strip()
                    if ',' in s:
                        s = s.split(',', 1)[1].strip().strip('"')
                    if s and len(s) > 2:
                        strings.append(s)
            if strings:
                print(f"  {m}: {strings}")
