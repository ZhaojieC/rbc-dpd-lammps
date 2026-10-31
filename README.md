# rbc-dpd-lammps

A red blood cell model for [LAMMPS](https://www.lammps.org): a triangulated
cell membrane in a dissipative particle dynamics (DPD) solvent, with no-slip
walls. The repository adds a few styles to a standard LAMMPS release and
comes with five small examples, from a cell at rest to a cell squeezing
through a slit.

A version for one NVIDIA GPU (KOKKOS package) is in
[rbc-dpd-lammps-gpu](https://github.com/ZhaojieC/rbc-dpd-lammps-gpu).

<p align="center"><img src="docs/slit.gif" width="640" alt="A red cell passing through a slit"></p>

## Contents

```
src/        LAMMPS styles: membrane springs, area and volume, bending, walls, cell shape
mesh/       membrane mesh of one cell: 500 vertices, 996 triangles
tools/      rbcdata.py, which writes LAMMPS data files with cells, solvent and walls
examples/   01_rest  02_poiseuille  03_channel  04_shear  05_slit
tests/      force checks against finite differences
build.sh    downloads LAMMPS and builds it with these styles
```

## Build

You need git, CMake 3.20 or newer, a C++17 compiler and, for parallel runs,
MPI. Then

```
git clone https://github.com/ZhaojieC/rbc-dpd-lammps.git
cd rbc-dpd-lammps
./build.sh
```

`build.sh` downloads LAMMPS (stable release of 30 Sep 2026), copies `src/`
into it and builds `build/lmp` with the MOLECULE, DPD-BASIC and EXTRA-FIX
packages. The build takes about 3 minutes with `NPROC=12 ./build.sh`
(12 parallel compile jobs; the default is 4). To add the styles to a LAMMPS
tree of your own, copy `src/*.cpp` and `src/*.h` into its `src/` folder and
build it with MOLECULE and DPD-BASIC (and EXTRA-FIX for the force checks
below).

To check the build, run

```
cd tests/forces
LMP="mpirun -np 4 ../../build/lmp" ./run_tests.sh
```

It compares the forces of each membrane term with finite differences of
its energy and ends with `all force checks passed`.

## Examples

Each example writes its own data file (Python 3 with NumPy), then runs
LAMMPS:

```
cd examples/01_rest
python3 make_data.py
mpirun -np 8 ../../build/lmp -in in.rest
```

| Example | What it shows | Particles | Steps | Time |
|---|---|---|---|---|
| [01_rest](examples/01_rest) | a cell at rest keeps its shape, area and volume | 10,740 | 50,000 | 4 min |
| [02_poiseuille](examples/02_poiseuille) | flow between two walls, no cell: the solvent viscosity | 5,196 | 50,000 | 2 min |
| [03_channel](examples/03_channel) | a cell in pressure-driven flow bends into a parachute | 20,483 | 100,000 | 15 min |
| [04_shear](examples/04_shear) | a cell in shear flow tank-treads | 8,178 | 250,000 | 16 min |
| [05_slit](examples/05_slit) | a cell pushed through a slit | 15,483 | ~50,000 | 6 min |

The times are for 12 MPI processes on 12 cores of an AMD EPYC 9554. Each
example folder has a README with the results to expect. The cell is written
to `cell.lammpstrj` (vertex positions); open it in OVITO or VMD to watch it.

## The model

The membrane is a closed triangulated surface (Fedosov, Caswell and
Karniadakis, 2010). Each vertex is an atom of type 1 and each cell is one
molecule. The mesh edges are bonds, the triangles are angles, and each pair
of triangles that share an edge is a dihedral.

| Style | Energy | Coefficients |
|---|---|---|
| `bond_style wlc/pow` | worm-like-chain spring plus a power-law repulsion on each edge | `bond_coeff 1 2.2 120 2`: lmax/l0, shear modulus mu0, exponent m |
| `angle_style area/volume` | penalties on the total area A and volume V of each cell and on the area of each triangle | `angle_coeff 1 4900 132.87 5000 92.45 100`: ka, A0, kv, V0, kd |
| `dihedral_style bend` | kb [1 - cos(theta - theta0)] for each pair of neighboring triangles | `dihedral_coeff 1 6.025 0`: kb, theta0 (degrees) |

Each spring and each triangle takes its rest length or area from the
reference shape, which is the shape of the cell at the first run after
`read_data`. The reference shape is stored in restart files, so continue a
run with `read_restart`; starting from a new data file would make the
deformed shape the new reference.

The solvent is DPD (`pair_style dpd/ext`). Solvent fills the box inside and
outside the cell; the membrane is coupled to it by the DPD drag, and solvent
particles are not reflected at the membrane. Walls are frozen DPD particles
(type 3) that fill blocks of the box.

Two more styles are new:

- `fix ID group wall/bounceback [slip group-ID [round R]] block xlo xhi ylo yhi zlo zhi [velocity vx vy vz] ...`
  keeps particles out of the wall blocks. A particle that enters a block
  goes back along its path, with its velocity reversed relative to the
  wall, which gives no slip. Particles of the `slip` group are reflected
  like a mirror instead (only the velocity normal to the wall is
  reversed), so they can slide along the wall. With `round R` they see
  the edges and corners of the blocks rounded with radius R (each block
  must then be at least 2R thick). `05_slit` uses both for the
  membrane. `INF` and `-INF` leave a face open. The fix
  returns the number of reflections in the last step (`f_ID[1]`) and how
  many reflections so far had to put a particle back at its old position
  (`f_ID[2]`, a running total that should stay small).
- `compute ID all rbc/shape` gives one row per molecule ID with the area,
  volume and reduced volume of each cell.

`tools/rbcdata.py` writes the data files: cells, solvent and wall particles,
and the matching `fix wall/bounceback` command (`walls.inc`).

## Parameters and units

The examples use the healthy-cell parameters of
[Chai et al. (2026)](https://doi.org/10.1016/j.bpj.2026.10.021) (Table S1),
in DPD units:

| | |
|---|---|
| solvent | number density 4, kBT 0.0707, `pair_style dpd/ext 0.0707 1.5`, `pair_coeff * * 4.0 40.0 0.0 0.15 0.15` |
| membrane-solvent and membrane-wall | `pair_coeff 1 2*3 0.0 47.9 0.0 0.2 0.2` (drag only; `05_slit` has no membrane-wall drag) |
| membrane | as in the table above |
| time step | 0.001 |

One length unit is 1 um, one energy unit 3.94e-20 J and one time unit
1.40e-4 s (same paper). Then one unit of force is 0.0394 pN, of stress
0.0394 Pa and of velocity 7.14 mm/s, and the solvent viscosity, 218 in DPD
units, is 1.2 mPa s.

## Things to know

- Wall blocks must lie inside the box, except for faces set to `INF` or
  `-INF`.
- The solvent slips a little at the walls: in `02_poiseuille` the fitted
  velocity profile reaches zero about 0.3 um inside each wall.
- The DPD solvent is compressible. A body force on the solvent cannot
  push a cell through a narrow slit without large density changes, so
  `05_slit` pushes the cell itself.
- `angle_style area/volume` needs molecule IDs, an orthogonal box, and cells
  smaller than half the periodic box.

## Tests

`tests/forces/run_tests.sh` checks the analytic forces of each membrane term
against finite differences of the energy (`fix numdiff`); the relative
difference is below 2e-8. It also moves the cell across the periodic boundary
and checks that the forces do not change (below 1e-12). The forces do not
depend on the number of MPI processes or on `newton_bond` (checked with 1, 4
and 8 processes), and they agree with the older in-house code within the
precision of its output (8e-6).

## Credits

The styles were rewritten for current LAMMPS from the in-house code of the
CRUNCH group at Brown University. The original bounce-back walls were written
by Igor Pivkin and the WLC-POW springs by Alireza Yazdani and Dmitry Fedosov.

- D. A. Fedosov, B. Caswell, G. E. Karniadakis. A multiscale red blood cell
  model with accurate mechanics, rheology, and dynamics. Biophys. J. 98,
  2215-2225 (2010). https://doi.org/10.1016/j.bpj.2010.02.002
- I. V. Pivkin, G. E. Karniadakis. Accurate coarse-grained modeling of red
  blood cells. Phys. Rev. Lett. 101, 118105 (2008).
  https://doi.org/10.1103/PhysRevLett.101.118105
- A. P. Thompson et al. LAMMPS - a flexible simulation tool for
  particle-based materials modeling at the atomic, meso, and continuum
  scales. Comput. Phys. Commun. 271, 108171 (2022).
  https://doi.org/10.1016/j.cpc.2021.108171

## License

GPL-2.0, the license of LAMMPS (see `LICENSE`).

## Related publications

1. Z. Chai, G. Li, P. A. Ndour, P. Connes, P. A. Buffet, M. Franco,
   G. E. Karniadakis. In silico biophysics and rheology of blood and red
   blood cells in Gaucher Disease. PLOS Comput. Biol. 21, e1012705 (2025).
   https://doi.org/10.1371/journal.pcbi.1012705
2. Z. Chai, N. Ahmadi Daryakenari, G. E. Karniadakis. A multiscale
   signaling-biophysical framework reveals mechanisms of macrophage-mediated
   RBC clearance in sickle cell and Gaucher disease. PNAS Nexus 5, pgag348
   (2026). https://doi.org/10.1093/pnasnexus/pgag348
3. Z. Chai, J. Zheng, H. Li, M. Dao, G. E. Karniadakis. Quantifying the
   biophysical properties of stomatocytes in health and disease. Biophys. J.
   (2026). https://doi.org/10.1016/j.bpj.2026.10.007
4. Z. Chai, M. de Person, P. A. Buffet, M. Franco, G. E. Karniadakis.
   Quantifying the biophysical properties of red blood cells in Gaucher
   disease. Biophys. J. (2026). https://doi.org/10.1016/j.bpj.2026.10.021

Preprints:

5. J. D. Toscano, Z. Chai, G. E. Karniadakis. GRAFT-ATHENA: Self-improving
   agentic teams for autonomous discovery and evolutionary numerical
   algorithms. arXiv:2605.11117 (2026). https://arxiv.org/abs/2605.11117
6. Z. Chai, J. Zheng, H. Li, M. Dao, G. E. Karniadakis. Quantifying
   reticulocyte biomechanics in health and disease. arXiv:2607.21810 (2026).
   https://arxiv.org/abs/2607.21810
7. Z. Chai, J. Zheng, H. Li, M. Dao, G. E. Karniadakis. The typical red cell
   makes too little vacuole material for coalescence to build the large
   vacuoles of pocked cells. arXiv:2610.22646 (2026).
   https://arxiv.org/abs/2610.22646
