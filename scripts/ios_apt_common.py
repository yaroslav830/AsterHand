"""Small, platform-independent Debian metadata helpers. Never executes a DEB."""
import re
from functools import cmp_to_key


def records(text):
    result = []
    for paragraph in text.replace('\r\n', '\n').strip().split('\n\n'):
        fields, key = {}, None
        for line in paragraph.splitlines():
            if line.startswith((' ', '\t')):
                if key is None:
                    raise ValueError('Invalid control continuation')
                fields[key] += '\n' + line
            else:
                key, value = line.split(':', 1)
                if key in fields:
                    if key == 'Tag':
                        fields[key] += ', ' + value.strip()
                        continue
                    raise ValueError('Duplicate control field: ' + key)
                fields[key] = value.strip()
        if fields:
            result.append(fields)
    return result


def version_compare(left, right):
    """Debian epoch:upstream-revision ordering, including tilde and absent revision."""
    def split(value):
        epoch, rest = value.split(':', 1) if ':' in value else ('0', value)
        upstream, revision = rest.rsplit('-', 1) if '-' in rest else (rest, '0')
        return int(epoch), upstream, revision
    def order(c):
        if c == '~': return -1
        if not c: return 0
        if c.isascii() and c.isalpha(): return ord(c)
        return ord(c) + 256
    def part(a, b):
        while a or b:
            while (a and not a[0].isdigit()) or (b and not b[0].isdigit()):
                x = a[0] if a and not a[0].isdigit() else ''
                y = b[0] if b and not b[0].isdigit() else ''
                if order(x) != order(y): return (order(x) > order(y)) - (order(x) < order(y))
                if x: a = a[1:]
                if y: b = b[1:]
            ma, mb = re.match(r'\d*', a)[0], re.match(r'\d*', b)[0]
            na, nb = int(ma or '0'), int(mb or '0')
            if na != nb: return (na > nb) - (na < nb)
            a, b = a[len(ma):], b[len(mb):]
        return 0
    a, b = split(left), split(right)
    return (a[0] > b[0]) - (a[0] < b[0]) or part(a[1], b[1]) or part(a[2], b[2])


def satisfies(version, operator=None, target=None):
    if not operator: return True
    comparison = version_compare(version, target)
    return {'=': comparison == 0, '>=': comparison >= 0, '<=': comparison <= 0,
            '>>': comparison > 0, '<<': comparison < 0}[operator]


def dependencies(fields):
    """Supported upstream dependencies have no build profiles or arch restrictions."""
    for field in ['Pre-Depends', 'Depends']:
        for group in fields.get(field, '').split(','):
            alternatives = []
            for atom in group.split('|'):
                if not atom.strip(): continue
                match = re.fullmatch(r'\s*([a-z0-9][a-z0-9+.-]*)(?::(?:any|native))?\s*(?:\((>=|<=|=|>>|<<)\s*([^()\s]+)\))?\s*', atom)
                if not match: raise ValueError('Unsupported dependency: ' + atom)
                alternatives.append(match.groups())
            if alternatives: yield alternatives


def dependency_closure(catalogue, architecture, seeds, external):
    available = {}
    for record in catalogue:
        if record['Architecture'] in [architecture, 'all']:
            available.setdefault(record['Package'], []).append(record)
    # Same-version transitional packages sometimes have multiple filenames. Stable
    # index order is authoritative for that tie; exact dependencies choose the code.
    for values in available.values():
        values.sort(key=cmp_to_key(lambda a, b: -version_compare(a['Version'], b['Version'])))
    chosen, required, base = {}, [( [(name, None, None)], '<seed>') for name in seeds], {}
    while required:
        alternatives, parent = required.pop(0)
        satisfied = False
        for name, operator, version in alternatives:
            if name in external:
                base[name] = external[name]
                satisfied = True; break
            if name in chosen:
                if satisfies(chosen[name]['Version'], operator, version):
                    satisfied = True; break
                continue
            candidate = next((r for r in available.get(name, []) if satisfies(r['Version'], operator, version)), None)
            if candidate:
                chosen[name] = candidate
                required.extend((group, name) for group in dependencies(candidate))
                satisfied = True; break
        if not satisfied:
            raise ValueError('Unresolved dependency of ' + parent + ': ' + repr(alternatives))
    return sorted(chosen.values(), key=lambda r: r['Package']), base
