"""Build a minimal PTY session launcher without UIKit initializers."""
import pathlib
import sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_windows as base
OUT=ROOT/'build/terminal-helper'
OUT.mkdir(parents=True,exist_ok=True)
base.BUILD=OUT
base.run([base.ZIG,'cc','-target','aarch64-ios.15.0','-isysroot',base.SDK,'-isystem',base.SDK/'usr/include','-O2','-c',ROOT/'Terminal/PCPTYHost.c','-o',OUT/'PCPTYHost.o'])
base.run([ROOT/'.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe','-flavor','darwin','-arch','arm64','-platform_version','ios','15.0','16.5','-syslibroot',base.SDK,'-L'+str(base.SDK/'usr/lib'),'-lSystem','-headerpad','0x1000',OUT/'PCPTYHost.o','-o',OUT/'pocketpty'])
