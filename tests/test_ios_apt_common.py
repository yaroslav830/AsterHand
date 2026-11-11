import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from ios_apt_common import version_compare, dependency_closure, records


class DebianSelectionTests(unittest.TestCase):
    def test_debian_ordering(self):
        pairs=[('1.0~rc1','1.0'),('1.0','1.0-1'),('1.0-2','1.0-10'),
               ('9.9','1:0'),('1.0a','1.0+'),('1.0~~','1.0~'),('0:1.00','1.0-0')]
        for left,right in pairs:
            expected=0 if left=='0:1.00' else -1
            self.assertEqual(version_compare(left,right),expected,(left,right))
            self.assertEqual(version_compare(right,left),-expected,(left,right))

    def test_native_closure_and_exact_dependencies(self):
        def package(name,version,arch,depends=''):
            return {'Package':name,'Version':version,'Architecture':arch,'Depends':depends}
        catalogue=[package('openssh','1:0','iphoneos-arm64','server'),
                   package('server','9.7','iphoneos-arm64','client (= 9.7), runtime (>= 2), firmware (>= 15)'),
                   package('client','9.7','iphoneos-arm64'),package('client','9.2','iphoneos-arm64e'),
                   package('runtime','1','iphoneos-arm64'),package('runtime','2','iphoneos-arm64'),
                   package('server','99','iphoneos-arm64e')]
        selected,base=dependency_closure(catalogue,'iphoneos-arm64',['openssh'],{'firmware':'device'})
        self.assertEqual({r['Package']:r['Version'] for r in selected},{'openssh':'1:0','server':'9.7','client':'9.7','runtime':'2'})
        self.assertEqual(base,{'firmware':'device'})
        self.assertEqual({r['Architecture'] for r in selected},{'iphoneos-arm64'})

    def test_missing_dependency_fails(self):
        with self.assertRaisesRegex(ValueError,'Unresolved'):
            dependency_closure([{'Package':'openssh','Version':'1','Architecture':'iphoneos-arm64','Depends':'missing (>= 2)'}],
                               'iphoneos-arm64',['openssh'],{})

    def test_dependency_alternative_and_cycle(self):
        catalogue=records('Package: openssh\nVersion: 1\nArchitecture: iphoneos-arm\nDepends: absent | runtime (>= 2)\n\nPackage: runtime\nVersion: 2\nArchitecture: iphoneos-arm\nDepends: openssh\n')
        selected,_=dependency_closure(catalogue,'iphoneos-arm',['openssh'],{})
        self.assertEqual(len(selected),2)

    def test_duplicate_identity_rejected(self):
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            records('Package: a\nPackage: b\n')


if __name__=='__main__': unittest.main()
