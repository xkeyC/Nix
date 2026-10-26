# 修复 patchelf 产生的重叠 LOAD 段：后映射的只读段会覆盖前一个可写段的同一页，
# 使 .dynamic 变成只读，ld.so 写 DT_DEBUG 时段错误。给后一个段补上前一个段的权限。
import struct,sys
for path in sys.argv[1:]:
    with open(path,'r+b') as f:
        d=bytearray(f.read())
        if d[:4]!=b'\x7fELF' or d[4]!=2:continue
        phoff,=struct.unpack_from('<Q',d,32);phes,phn=struct.unpack_from('<HH',d,54)
        loads=[]
        for i in range(phn):
            o=phoff+i*phes;t,fl=struct.unpack_from('<II',d,o);va,=struct.unpack_from('<Q',d,o+16);ms,=struct.unpack_from('<Q',d,o+40)
            if t==1:loads.append([i,o,fl,va&~0xfff,(va+ms+0xfff)&~0xfff])
        changed=False
        for a in loads:
            for b in loads:
                if a[0]<b[0] and a[3]<b[4] and b[3]<a[4] and (a[2]|b[2])!=b[2]:
                    b[2]|=a[2];struct.pack_into('<I',d,b[1]+4,b[2]);changed=True
        if changed:
            f.seek(0);f.write(d);print('fixed overlapping LOAD segments:',path)
