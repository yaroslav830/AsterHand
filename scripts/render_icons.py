"""Render the user's AsterHand reference as a reusable monochrome vector mark."""
from pathlib import Path
import sys
from sync_brand_icons import Image
from PIL import ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Resources/Icons'
# Cubic outlines traced from the user-provided reference; coordinates in 1024 units.
SHAPES=[[(296,478),('L',399,312),('C',430,265,467,250,507,253),('C',559,250,593,273,625,326),('L',791,586),('C',823,640,817,688,788,727),('C',758,768,709,789,649,789),('C',642,789,642,785,648,780),('C',685,743,692,700,670,660),('L',550,469),('C',522,425,488,418,455,421),('C',412,419,360,440,302,478),('C',294,482,294,480,296,478)],[(430,486),('C',400,483,353,503,309,534),('C',249,574,221,616,222,670),('C',223,736,272,786,330,789),('L',560,789),('C',600,789,635,757,636,716),('C',640,674,605,644,566,644),('L',465,644),('C',414,644,384,624,386,574),('C',387,545,409,514,431,492),('C',437,485,434,486,430,486)]]
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[];scale=4
    mark=Image.new('RGBA',(1024*scale,1024*scale));draw=ImageDraw.Draw(mark)
    for shape in SHAPES:
        first=shape[0];points=[first];current=first;svg=f'M{first[0]} {first[1]}'
        for seg in shape[1:]:
            svg+=' '+seg[0]+' '+' '.join(str(n) for n in seg[1:])
            if seg[0]=='L':current=(seg[1],seg[2]);points.append(current)
            else:
                x,y=current;x1,y1,x2,y2,x3,y3=seg[1:]
                for i in range(1,41):
                    t=i/40;u=1-t;points.append((u*u*u*x+3*u*u*t*x1+3*u*t*t*x2+t*t*t*x3,u*u*u*y+3*u*u*t*y1+3*u*t*t*y2+t*t*t*y3))
                current=(x3,y3)
        draw.polygon([(round(x*scale),round(y*scale)) for x,y in points],fill='#121212')
        paths.append('<path fill="#121212" d="'+svg+' Z"/>')
    svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{bg}'+''.join(paths)+'</svg>\n'
    icon_svg=svg.replace('{bg}','<path fill="white" d="M0 0h1024v1024H0z"/>')
    dark_only='--dark-only' in sys.argv
    if not dark_only:
        (ROOT/'Resources/AgentGoIcon.svg').write_text(icon_svg,encoding='utf-8')
        (ROOT/'Resources/AgentGoMark.svg').write_text(svg.replace('{bg}',''),encoding='utf-8')
        (ROOT/'desktop/public/agentgo.svg').write_text(icon_svg,encoding='utf-8')
    icon=Image.new('RGBA',mark.size,'white');icon.alpha_composite(mark);icon=icon.convert('RGB')
    for name,size in {'AgentGoIcon1024.png':1024,'AppIcon60x60@2x.png':120,'AppIcon60x60@3x.png':180,'AppIcon40x40@2x.png':80,'AppIcon40x40@3x.png':120,'AppIcon29x29@2x.png':58,'AppIcon29x29@3x.png':87,'AppIcon20x20@2x.png':40,'AppIcon20x20@3x.png':60}.items():
        if not dark_only:icon.resize((size,size),Image.Resampling.LANCZOS).save(OUT/name)
        # Same vector silhouette and antialiasing, inverse monochrome palette.
        mask=mark.getchannel('A');dark=Image.new('RGB',mark.size,'#121212');dark.paste('#eeeeee',(0,0),mask)
        dark.resize((size,size),Image.Resampling.LANCZOS).save(OUT/name.replace('AppIcon','AppIconDark').replace('AgentGoIcon','AgentGoIconDark'))
    if not dark_only:
        for suffix,size in [('',34),('@2x',68),('@3x',102)]:mark.resize((size,size),Image.Resampling.LANCZOS).save(OUT/('AgentGoMark'+suffix+'.png'))
    # Keep the approved rounded variants authoritative after legacy mark export.
    from sync_brand_icons import sync as sync_brand_icons
    sync_brand_icons()
    print('AsterHand reference mark and approved rounded icons synchronized')
if __name__=='__main__':main()
