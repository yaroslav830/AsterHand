using System;
using System.Linq;
using System.Reflection;
using System.Runtime.Versioning;

namespace AsterHand {
    internal static partial class NativeTests {
        static void InspectPackage(string file) {var assembly=Assembly.LoadFile(System.IO.Path.GetFullPath(file));var names=assembly.GetTypes().Select(t=>t.FullName).ToArray();var framework=(TargetFrameworkAttribute)assembly.GetCustomAttributes(typeof(TargetFrameworkAttribute),false).First();PortableExecutableKinds kind;System.Reflection.ImageFileMachine machine;assembly.ManifestModule.GetPEKind(out kind,out machine);Console.WriteLine(J.Write(J.Obj("version",assembly.GetName().Version.ToString(),"targetFramework",framework.FrameworkName,"peKind",kind.ToString(),"machine",machine.ToString(),"embeddedResources",assembly.GetManifestResourceNames(),"references",assembly.GetReferencedAssemblies().Select(a=>a.Name).ToArray(),"hasLicensing",names.Any(n=>n.Contains("License")),"hasTestCode",names.Any(n=>n.Contains("NativeTests")))));}
    }
}
