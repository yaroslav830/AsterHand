#!/usr/bin/env python3
"""Activate AsterHand's shell-UID bridge over an already-authorized USB ADB connection.

A signature-DUMP-protected ordered receiver returns an application-only local IPC
seed to the authorized shell. Its random secret is captured in memory and sent
on stdin, never in process arguments or printed output. Root and run-as are not
used, including on ROMs whose run-as SELinux policy is inconsistent.
"""
from __future__ import annotations
import argparse, base64, json, re, secrets, shutil, struct, subprocess, sys

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial',required=True,help='Exact adb device serial')
    parser.add_argument('--adb',default=shutil.which('adb') or 'adb')
    parser.add_argument('--stop',action='store_true',help='Stop this application bridge and its terminal sessions')
    args=parser.parse_args();base=[args.adb,'-s',args.serial]
    def run(*command,limit=15):
        result=subprocess.run(base+list(command),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=limit)
        if result.returncode:raise RuntimeError('ADB operation failed; verify USB debugging and the installed AsterHand receiver')
        return result.stdout
    if run('shell','id','-u').strip()!=b'2000':raise RuntimeError('ADB must run as UID 2000; adb-root is not accepted')
    nonce=secrets.token_hex(16);operation='stop' if args.stop else 'activate'
    output=run('shell','am','broadcast','--include-stopped-packages','-n','com.pocketagent/.AdbActivationReceiver','-a','com.pocketagent.ACTIVATE_ADB','--es','operation',operation,'--es','nonce',nonce,limit=18).decode('utf-8','replace')
    if args.stop:
        if not re.search(r'ASTERHAND_ADB_STOPPED:'+nonce+r':(?:stopped|not_running)',output):raise RuntimeError('Authorized bridge stop was not acknowledged')
        print(json.dumps({'device':args.serial,'bridge':'stopped','root_used':False}));return
    match=re.search(r'ASTERHAND_ADB_V1:'+nonce+r':([A-Za-z0-9_-]+)',output)
    if not match:raise RuntimeError('Authorized bridge activation did not return a valid local IPC seed')
    encoded=match.group(1);config=json.loads(base64.urlsafe_b64decode(encoded+'='*((-len(encoded))%4)))
    if not isinstance(config.get('uid'),int) or config['uid']<10000 or len(config.get('token',''))<40:raise RuntimeError('Invalid application bootstrap identity')
    apk=config.get('apk','')
    if not re.fullmatch(r'/data/app/[A-Za-z0-9_./=+~-]+\.apk',apk):raise RuntimeError('Invalid installed APK path')
    payload=json.dumps(config,separators=(',',':')).encode('utf-8')
    command="CLASSPATH='"+apk.replace("'","'\\''")+"' /system/bin/app_process /system/bin com.pocketagent.AdbBridgeBootstrap"
    result=subprocess.run(base+['shell',command],input=struct.pack('>I',len(payload))+payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
    if result.returncode or result.stdout.decode('utf-8','replace').strip()!='ASTERHAND_ADB_READY uid=2000':raise RuntimeError('The UID2000 bridge did not start; no Root fallback was attempted')
    print(json.dumps({'device':args.serial,'bridge':'ready','uid':2000,'transport':'authenticated 127.0.0.1 HMAC','root_used':False}))

if __name__=='__main__':
    try:main()
    except Exception as error:print('AsterHand ADB setup failed: '+str(error),file=sys.stderr);sys.exit(1)
