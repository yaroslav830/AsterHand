"""Small installer/uninstaller helper without UIKit startup."""
import argparse,pathlib,subprocess
import build_windows as base
from ios_build_profile import add_environment_args,profile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();add_environment_args(parser);args=parser.parse_args();target=profile(args)
    output=ROOT/'build'/target.helper_directory('maintenance');output.mkdir(parents=True,exist_ok=True);base.BUILD=output
    base.run([base.ZIG,'cc','-target',target.target,'-isysroot',base.SDK,'-iframework',base.SDK/'System/Library/Frameworks',
        '-isystem',base.SDK/'usr/include','-I'+str(ROOT/'Sources'),'-I'+str(ROOT/'.build-deps/roothide-devkit/devkit'),
        '-I'+str(ROOT/'.build-deps/TrollVNC-source/include-spi'),*target.defines,*target.availability,'-fobjc-arc','-fblocks','-O2',
        '-c',ROOT/'Maintenance/PCMaintenance.m','-o',output/'PCMaintenance.o'])
    base.run([ROOT/'.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe','-flavor','darwin','-arch','arm64','-platform_version','ios',target.minimum,'16.5',
        '-syslibroot',base.SDK,'-F'+str(base.SDK/'System/Library/Frameworks'),'-L'+str(base.SDK/'usr/lib'),'-L'+str(ROOT/'.build-deps/roothide-devkit/devkit/roothide'),
        *target.libraries,'-lproc','-lSystem','-lobjc','-framework','Foundation','-framework','Security','-headerpad','0x1000',output/'PCMaintenance.o','-o',output/'pocketmaint'])
    print('Maintenance helper built: '+str(output/'pocketmaint'))
if __name__=='__main__':main()
