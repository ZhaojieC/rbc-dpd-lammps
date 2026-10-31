#!/bin/bash
# Download LAMMPS, add the RBC styles of src/ and build the lmp binary.
#
#   ./build.sh                  # builds ./build/lmp
#   NPROC=16 ./build.sh         # more parallel compile jobs (default 4)
#
# Needs git, CMake 3.20 or newer, a C++17 compiler and, for parallel
# runs, MPI.  On a cluster, load them first, for example
#   module load gcc openmpi cmake
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${LAMMPS_TAG:-stable_30Sep2026}
LAMMPS=${LAMMPS_DIR:-$HERE/lammps}
NPROC=${NPROC:-4}

if [ ! -d "$LAMMPS" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/lammps/lammps.git "$LAMMPS"
fi
cp "$HERE"/src/*.cpp "$HERE"/src/*.h "$LAMMPS"/src/

cmake -S "$LAMMPS"/cmake -B "$HERE"/build -D CMAKE_BUILD_TYPE=Release \
  -D PKG_MOLECULE=yes -D PKG_DPD-BASIC=yes -D PKG_EXTRA-FIX=yes
cmake --build "$HERE"/build -j "$NPROC"
echo "built $HERE/build/lmp"
