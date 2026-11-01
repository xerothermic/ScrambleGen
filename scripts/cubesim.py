"""Sticker-level 3x3 simulator with face, wide, slice and rotation moves.
Geometry copied from ScrambleGen scripts/verify_cube.py (U(v)=(-z,y,x) etc.)."""
FACES = ['U', 'D', 'F', 'B', 'L', 'R']

def _rot():
    return {
        'U': lambda v: (-v[2], v[1], v[0]), 'D': lambda v: (v[2], v[1], -v[0]),
        'R': lambda v: (v[0], v[2], -v[1]), 'L': lambda v: (v[0], -v[2], v[1]),
        'F': lambda v: (v[1], -v[0], v[2]), 'B': lambda v: (-v[1], v[0], v[2]),
    }
ROT = _rot()
AX = {'x': 0, 'y': 1, 'z': 2}
# move -> (rotation dir face, axis index, layers, sign) ; sign -1 means inverse of the dir face
MOVES = {
    'U': ('U', 1, (1,), 1), 'D': ('D', 1, (-1,), 1), 'R': ('R', 0, (1,), 1),
    'L': ('L', 0, (-1,), 1), 'F': ('F', 2, (1,), 1), 'B': ('B', 2, (-1,), 1),
    'u': ('U', 1, (0, 1), 1), 'd': ('D', 1, (-1, 0), 1), 'r': ('R', 0, (0, 1), 1),
    'l': ('L', 0, (-1, 0), 1), 'f': ('F', 2, (0, 1), 1), 'b': ('B', 2, (-1, 0), 1),
    'M': ('L', 0, (0,), 1), 'E': ('D', 1, (0,), 1), 'S': ('F', 2, (0,), 1),
    'x': ('R', 0, (-1, 0, 1), 1), 'y': ('U', 1, (-1, 0, 1), 1), 'z': ('F', 2, (-1, 0, 1), 1),
}

def parse(alg):
    out = []
    for t in alg.split():
        m, rest = t[0], t[1:]
        if m not in MOVES or rest not in ('', "'", '2'):
            raise ValueError(f'bad token {t!r}')
        out.append((m, {'': 1, "'": 3, '2': 2}[rest]))
    return out

def invert(alg):
    toks = alg.split()[::-1]
    return ' '.join(t[0] + {'': "'", "'": '', '2': '2'}[t[1:]] for t in toks)

class Cube:
    def __init__(self):
        # sticker: (pos, normal) -> colour (face letter of original normal)
        self.s = {}
        norm = {'U': (0, 1, 0), 'D': (0, -1, 0), 'F': (0, 0, 1), 'B': (0, 0, -1), 'L': (-1, 0, 0), 'R': (1, 0, 0)}
        for x in (-1, 0, 1):
            for y in (-1, 0, 1):
                for z in (-1, 0, 1):
                    for f, n in norm.items():
                        if (x, y, z)[AX_OF[f]] == sum(n):
                            self.s[((x, y, z), n)] = f
    def move(self, m, times):
        face, ax, layers, _ = MOVES[m]
        fn = ROT[face]
        for _ in range(times):
            new = {}
            for (p, n), c in self.s.items():
                if p[ax] in layers:
                    new[(fn(p), fn(n))] = c
                else:
                    new[(p, n)] = c
            self.s = new
    def apply(self, alg):
        for m, t in parse(alg):
            self.move(m, t)
        return self
    def copy(self):
        c = Cube.__new__(Cube); c.s = dict(self.s); return c
AX_OF = {'U': 1, 'D': 1, 'F': 2, 'B': 2, 'L': 0, 'R': 0}

def solved():
    return Cube()
