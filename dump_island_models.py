import sys, logging
logging.disable(logging.CRITICAL)
sys.path.insert(0, r'C:/Users/taoxg/.workbuddy/binaries/python/envs/androguard/Lib/site-packages')
from androguard.core.dex import DEX

with open(r'E:/MSRR/fbs/tmp_pronto/si_extracted/classes3.dex', 'rb') as f:
    d = DEX(f.read())

# Extract all field names from island model classes
target_prefixes = [
    'Lcom/xzakota/hyper/notification/island/model/',
    'Lcom/xzakota/hyper/notification/island/template/',
    'Lcom/xzakota/hyper/notification/focus/model/',
    'Lcom/xzakota/hyper/notification/focus/template/',
]

for cls in d.get_classes():
    cls_name = cls.get_name()
    
    for prefix in target_prefixes:
        if cls_name.startswith(prefix) and cls_name.count('$') <= 1 and not 'serializer' in cls_name and not 'Companion' in cls_name and not 'Creator' in cls_name:
            # Skip inner classes
            short = cls_name[len(prefix):-1]
            print(f"\n=== {prefix.split('/')[-2].split('/')[-1]}.{short} ===")
            
            # Get instance fields from the class
            for field in cls.get_fields():
                f_name = field.get_name()
                f_desc = field.get_descriptor()
                # Skip synthetic fields like $serializer
                if f_name.startswith('$') or f_name == 'Companion':
                    continue
                print(f"  {f_name}: {f_desc}")
            break
