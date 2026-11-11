"""Build the public AsterHand website from source and existing sanitized assets."""
import argparse
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
VIDEO_NAMES = (
    'AsterHand-Five-Platforms-MCP-Demo-EN-1080p.mp4',
    'AsterHand-Five-Platforms-MCP-Demo-ZH-1080p.mp4',
    'AsterHand-Five-Platforms-Promo-EN-1080p.mp4',
    'AsterHand-Five-Platforms-Promo-ZH-1080p.mp4',
)


def build(output):
    output=output.resolve()
    source=(ROOT/'website').resolve()
    if output==source or source in output.parents and output.name!='dist':
        raise ValueError('Use website/dist or a separate build output directory')
    output.mkdir(parents=True,exist_ok=True)
    for name in ['index.html','styles.css','app.js','asterhand-mark.svg']:
        shutil.copyfile(source/name,output/name)
    images=ROOT/'docs/images'
    for name in (
        'ios-agent-en.png',
        'android-agent-en.png',
        'five-platforms-mcp-en.jpg',
        'five-platforms-mcp-zh.jpg',
    ):
        destination=output/'assets'/name;destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(images/name,destination)
    media_output = output / 'media'
    extra_videos = {p.name for p in media_output.glob('*.mp4')} - set(VIDEO_NAMES)
    if extra_videos:
        raise ValueError('Unexpected videos in the output. Choose a fresh build output directory.')
    media_output.mkdir(exist_ok=True)
    for name in VIDEO_NAMES:
        shutil.copyfile(source / 'media' / name, media_output / name)
    (output/'.nojekyll').write_bytes(b'')
    (output/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: https://yaroslav830.github.io/AsterHand/sitemap.xml\n',encoding='utf-8')
    (output/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://yaroslav830.github.io/AsterHand/</loc></url></urlset>\n',encoding='utf-8')
    print(json.dumps({'output':str(output),'files':len([p for p in output.rglob('*') if p.is_file()]),'languages':['en','zh-CN']}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'website/dist')
    build(parser.parse_args().output)
