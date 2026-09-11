# analyze_ipa.py -- 解析 ipa 内主程序的 Mach-O 头，定位"启动即闪退"类问题
# 用法: python build/analyze_ipa.py <path-to-ipa>
import sys, struct, zipfile, plistlib

LC = {
    0x1: 'LC_SEGMENT', 0x2: 'LC_SYMTAB', 0xb: 'LC_DYSYMTAB', 0xc: 'LC_LOAD_DYLIB',
    0xd: 'LC_ID_DYLIB', 0x1c: 'LC_RPATH', 0x1d: 'LC_CODE_SIGNATURE',
    0x1e: 'LC_SEGMENT_SPLIT_INFO', 0x21: 'LC_ENCRYPTION_INFO', 0x22: 'LC_DYLD_INFO',
    0x24: 'LC_VERSION_MIN_IPHONEOS', 0x26: 'LC_FUNCTION_STARTS',
    0x29: 'LC_DATA_IN_CODE', 0x2b: 'LC_SOURCE_VERSION', 0x2c: 'LC_MAIN',
    0x32: 'LC_BUILD_VERSION', 0x33: 'LC_DYLD_EXPORTS_TRIE',
    0x34: 'LC_DYLD_CHAINED_FIXUPS', 0x80000022: 'LC_DYLD_INFO_ONLY',
    0x2A: 'LC_DYLIB_CODE_SIGN_DRS', 0x2f: 'LC_LINKER_OPTION',
    0x2e: 'LC_ENCRYPTION_INFO_64',
}
PLATFORM = {1: 'macOS', 2: 'iOS', 3: 'tvOS', 4: 'watchOS', 6: 'macCatalyst', 7: 'iOS-Simulator'}


def ver(x):
    return '%d.%d.%d' % ((x >> 16) & 0xffff, (x >> 8) & 0xff, x & 0xff)


def main(path):
    z = zipfile.ZipFile(path)
    name = [n for n in z.namelist() if n.endswith('.app/')]
    if not name:
        print('包里找不到 .app'); return
    appdir = name[0]
    info = plistlib.loads(z.read(appdir + 'Info.plist'))
    exe = info['CFBundleExecutable']
    data = z.read(appdir + exe)

    print('=== 包内 Info.plist ===')
    for k in ('CFBundleIdentifier', 'CFBundleExecutable', 'MinimumOSVersion',
              'LSMinimumSystemVersion', 'DTPlatformVersion', 'DTXcode', 'DTCompiler',
              'CFBundleSupportedPlatforms', 'UIRequiredDeviceCapabilities', 'UIDeviceFamily',
              'UIFileSharingEnabled', 'LSSupportsOpeningDocumentsInPlace'):
        if k in info:
            print('  %-30s = %s' % (k, info[k]))

    print('\n=== Mach-O 头 ===')
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags = struct.unpack('<7I', data[:28])
    is64 = (magic == 0xfeedfacf)
    print('  magic        = 0x%08x %s' % (magic, '(64-bit)' if is64 else ''))
    print('  cputype      = %d (%s)' % (cputype, 'arm64' if cputype == 0x0100000c else 'other'))
    print('  filetype     = %d (%s)' % (ftype, {2: 'MH_EXECUTE', 6: 'MH_DYLIB', 8: 'MH_BUNDLE'}.get(ftype, '?')))
    print('  flags        = 0x%08x%s' % (flags, '  PIE' if flags & 0x200000 else ''))
    print('  load commands= %d' % ncmds)

    off = 32 if is64 else 28   # 64 位头多一个 4 字节 reserved 字段
    cmds = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', data[off:off + 8])
        cmds.append((cmd, cmdsize, off))
        off += cmdsize

    print('\n=== 关键 Load Command ===')
    found = {}
    for cmd, cmdsize, o in cmds:
        nm = LC.get(cmd, 'LC_0x%x' % cmd)
        found.setdefault(nm, 0)
        found[nm] += 1
        if nm == 'LC_BUILD_VERSION':
            plat, minos, sdk, ntools = struct.unpack('<IIII', data[o + 8:o + 24])
            print('  LC_BUILD_VERSION   platform=%s(%d)  minos=%s  sdk=%s' %
                  (PLATFORM.get(plat, '?'), plat, ver(minos), ver(sdk)))
        elif nm == 'LC_VERSION_MIN_IPHONEOS':
            v, sdkv = struct.unpack('<II', data[o + 8:o + 16])
            print('  LC_VERSION_MIN_IPHONEOS  version=%s  sdk=%s' % (ver(v), ver(sdkv)))
        elif nm in ('LC_ENCRYPTION_INFO', 'LC_ENCRYPTION_INFO_64'):
            cryptoff, cryptsize, cryptid = struct.unpack('<III', data[o + 8:o + 20])
            print('  %-18s cryptid=%d %s' % (nm, cryptid, '(未加密 ✓)' if cryptid == 0 else '(已加密 ✗)'))
        elif nm == 'LC_LOAD_DYLIB':
            noff = struct.unpack('<I', data[o + 24:o + 28])[0]
            s = data[o + noff:o + cmdsize].split(b'\x00')[0].decode('utf-8', 'replace')
            if 'WebKit' in s or 'UIKit' in s or 'Foundation' in s or 'libSystem' in s or 'libswift' in s:
                print('  LC_LOAD_DYLIB      %s' % s)
        elif nm == 'LC_CODE_SIGNATURE':
            doff, dsize = struct.unpack('<II', data[o + 8:o + 16])
            print('  LC_CODE_SIGNATURE  offset=%d size=%d %s' % (doff, dsize, '(已签名 ✓)' if dsize > 0 else '(未签名 ✗)'))

    print('\n=== 全部 load command 统计 ===')
    for k in sorted(found):
        print('  %-30s x%d' % (k, found[k]))

    print('\n=== 结论性检查 ===')
    chained = 'LC_DYLD_CHAINED_FIXUPS' in found
    minos = None
    for cmd, cmdsize, o in cmds:
        if cmd == 0x32:
            plat, mo, sdk, nt = struct.unpack('<IIII', data[o + 8:o + 24])
            minos = ver(mo)
    if minos is None:
        for cmd, cmdsize, o in cmds:
            if cmd == 0x24:
                minos = ver(struct.unpack('<I', data[o + 8:o + 12])[0])
    print('  最低系统版本            : %s' % minos)
    print('  使用链式修复(chained)   : %s' % ('是' if chained else '否'))
    if chained and minos and minos < '13.4':
        print('  ⚠️ 风险：二进制用了 chained fixups，但 minos=%s < 13.4 —— iOS 12/13.0~13.3 上 dyld 无法加载，会启动即闪退' % minos)
    else:
        print('  ✓ 未发现 dyld 层面的版本冲突')
    if 'LC_ENCRYPTION_INFO_64' in found or 'LC_ENCRYPTION_INFO' in found:
        pass
    else:
        print('  ✓ 没有加密段（TrollStore 可安装）')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\fanyo\Desktop\TrollLifeAI.ipa')
