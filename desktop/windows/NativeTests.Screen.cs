using System.Drawing;

namespace AsterHand {
    internal static partial class NativeTests {
        static void RemoteScreenGeometry() {
            PointF point;
            Check(RemoteScreen.Point(new Size(600,600),new Size(300,600),new Point(300,300),out point)&&point.X==.5f&&point.Y==.5f,"Portrait stream maps display center to device center");
            Check(!RemoteScreen.Point(new Size(600,600),new Size(300,600),new Point(50,300),out point),"Portrait letterbox does not dispatch a device tap");
            Check(RemoteScreen.Point(new Size(600,600),new Size(600,300),new Point(300,150),out point)&&point.Y==0&&point.X==.5f,"Landscape stream removes vertical letterbox offset");
            Check(!RemoteScreen.Point(new Size(0,600),new Size(600,300),new Point(0,0),out point),"Empty screen viewer cannot dispatch coordinates");
        }
    }
}
