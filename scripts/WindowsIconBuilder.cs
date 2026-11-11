using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

// Format conversion of the existing mobile artwork; do not redraw the user's mark.
internal static class WindowsIconBuilder {
    static int Main(string[] args) {
        var sizes=new[]{16,20,24,32,40,48,64,128,256};
        var frames=new List<byte[]>();
        using(var source=Image.FromFile(args[0]))foreach(int size in sizes) {
            using(var image=new Bitmap(size,size,PixelFormat.Format32bppArgb)) {
                using(var graphics=Graphics.FromImage(image)) {
                    graphics.Clear(Color.Transparent);
                    graphics.CompositingMode=CompositingMode.SourceCopy;
                    graphics.InterpolationMode=InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode=PixelOffsetMode.HighQuality;
                    graphics.CompositingQuality=CompositingQuality.HighQuality;
                    graphics.DrawImage(source,new Rectangle(0,0,size,size));
                }
                using(var bitmap=new MemoryStream()) {
                    image.Save(bitmap,ImageFormat.Bmp);
                    byte[] bmp=bitmap.ToArray();
                    if(BitConverter.ToInt32(bmp,14)!=40||BitConverter.ToInt16(bmp,28)!=32)
                        throw new InvalidDataException("Expected a 32-bit BITMAPINFOHEADER");
                    byte[] frame=new byte[bmp.Length-14+((size+31)/32)*4*size];
                    Buffer.BlockCopy(bmp,14,frame,0,bmp.Length-14);
                    Buffer.BlockCopy(BitConverter.GetBytes(size*2),0,frame,8,4);
                    // Older Windows uses the AND bitmap when alpha is unavailable.
                    // Its rows are bottom-up and padded to a 32-bit boundary.
                    int stride=((size+31)/32)*4,maskOffset=bmp.Length-14;
                    for(int y=0;y<size;y++)for(int x=0;x<size;x++)
                        if(image.GetPixel(x,y).A<128)
                            frame[maskOffset+(size-1-y)*stride+x/8]|=(byte)(0x80>>(x%8));
                    frames.Add(frame);
                }
            }
        }
        using(var file=new BinaryWriter(File.Create(args[1]))) {
            file.Write((ushort)0);file.Write((ushort)1);file.Write((ushort)sizes.Length);
            int offset=6+16*sizes.Length;
            for(int i=0;i<sizes.Length;i++) {
                file.Write((byte)(sizes[i]==256?0:sizes[i]));file.Write((byte)(sizes[i]==256?0:sizes[i]));
                file.Write((byte)0);file.Write((byte)0);file.Write((ushort)1);file.Write((ushort)32);
                file.Write(frames[i].Length);file.Write(offset);offset+=frames[i].Length;
            }
            foreach(byte[] frame in frames)file.Write(frame);
        }
        return 0;
    }
}
