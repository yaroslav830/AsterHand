"""Shared iOS target selection; historical command defaults remain unchanged."""
from dataclasses import dataclass

@dataclass(frozen=True)
class IOSProfile:
    environment: str

    @property
    def minimum(self):return '14.0' if self.environment == 'rootful' else '15.0'
    @property
    def target(self):return 'aarch64-ios.' + self.minimum
    @property
    def defines(self):return ['-DPC_ROOTHIDE=1'] if self.environment == 'roothide' else ['-DPC_ROOTFUL=1'] if self.environment == 'rootful' else []
    @property
    def libraries(self):return ['-lroothide'] if self.environment == 'roothide' else []
    @property
    def availability(self):return ['-Werror=unguarded-availability', '-Werror=unguarded-availability-new']
    def helper_directory(self, name):return name if self.environment == 'roothide' else name + '-' + self.environment

def add_environment_args(parser, default='rootless'):
    group=parser.add_mutually_exclusive_group()
    for name in ('roothide','rootless','rootful'):
        group.add_argument('--'+name, dest='environment', action='store_const', const=name)
    parser.set_defaults(environment=default)

def profile(args):return IOSProfile(args.environment)

def availability_object(base, target, output):
    obj=output/'PCAvailability.o'
    base.run([base.ZIG,'cc','-target',target.target,'-isysroot',base.SDK,
        '-iframework',base.SDK/'System/Library/Frameworks','-isystem',base.SDK/'usr/include',
        '-fobjc-arc','-fblocks','-O2',*target.availability,
        '-c',base.ROOT/'Sources/PCAvailability.m','-o',obj])
    return obj
