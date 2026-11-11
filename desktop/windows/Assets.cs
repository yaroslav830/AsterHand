using System;
using System.IO;
using System.Reflection;
using System.Text;

namespace AsterHand {
    internal static class Assets {
        public static byte[] Bytes(string path) {string name=Path.GetFileName(path);using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("AsterHand."+name)){if(stream!=null){using(var output=new MemoryStream()){stream.CopyTo(output);return output.ToArray();}}}return File.ReadAllBytes(path);}
        public static string Text(string path) {return Encoding.UTF8.GetString(Bytes(path));}
        public static bool Exists(string path) {return Assembly.GetExecutingAssembly().GetManifestResourceInfo("AsterHand."+Path.GetFileName(path))!=null||File.Exists(path);}
    }
}
