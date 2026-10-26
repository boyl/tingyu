"""从已校验的完整 Windows 目录生成逐文件校验的原生安装包。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def build(bundle: Path, output: Path, compiler: Path, test_identity: bool = False):
    bundle, output, compiler = bundle.resolve(), output.resolve(), compiler.resolve()
    required = ['tingyu.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'sqlite3.dll',
                'data/app.so', 'data/icudtl.dat', 'LICENSE.txt', 'msvcp140.dll', 'vcruntime140.dll']
    for name in required:
        if not (bundle / name).is_file():
            raise ValueError(f'缺少运行文件：{name}')
    output.mkdir(parents=True, exist_ok=True)
    files = []
    entries = []
    sources = [(file, str(file.relative_to(bundle))) for file in sorted(bundle.rglob('*'))
               if file.name != '使用说明.md']
    sources.append((Path(__file__).parent / 'installer/usage-zh-CN.txt', '使用说明.txt'))
    for file, relative in sources:
        if file.is_symlink() or file.is_junction():
            raise ValueError(f'载荷不能包含链接：{file}')
        if not file.is_file():
            continue
        if any(char in str(file) for char in ['"', "'", '{', '}']):
            raise ValueError(f'不支持的安装源路径：{file}')
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        destination = '{app}' + ('\\' + str(Path(relative).parent) if Path(relative).parent != Path('.') else '')
        entries.append(f'Source: "{file.resolve()}"; DestDir: "{destination}"; DestName: "{Path(relative).name}"; Flags: ignoreversion; '
                       f"AfterInstall: VerifyInstalledFile('{{app}}\\{relative}', '{digest}')")
        files.append({'path': relative, 'sha256': digest, 'bytes': file.stat().st_size})
    payload = output / 'payload.iss'
    payload.write_text('\n'.join(entries) + '\n', encoding='utf-8-sig')
    command = [str(compiler), '/Qp', f'/DSourcePath={bundle}', f'/DOutputPath={output}',
               f'/DPayloadList={payload}']
    if test_identity:
        command += ['/DAppId=tingyu.installer.regression', '/DAppName=tingyu 安装测试']
    command += [str(Path(__file__).parent / 'installer/tingyu.iss')]
    subprocess.run(command, check=True)
    exe = output / 'tingyu-0.1.28-windows-x64-setup.exe'
    manifest = {'installer': exe.name, 'sha256': hashlib.sha256(exe.read_bytes()).hexdigest(),
                'bytes': exe.stat().st_size, 'testIdentity': test_identity, 'files': files}
    (output / 'installer-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'files'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--test-identity', action='store_true')
    args = parser.parse_args()
    build(args.bundle, args.output, args.compiler, args.test_identity)
