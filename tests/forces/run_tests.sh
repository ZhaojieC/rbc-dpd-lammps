#!/bin/bash
# Run the force checks.  LMP is the LAMMPS command, for example
#   LMP="mpirun -np 4 ../../build/lmp" ./run_tests.sh
set -e
LMP=${LMP:-lmp}
python3 make_data.py
status=0
for term in bond angle dihedral all; do
  for shift in 0 9; do
    $LMP -in in.forces -var term $term -var shift $shift -log none -screen none
  done
  python3 compare.py forces_${term}_0.dump forces_${term}_9.dump || status=1
done
if [ $status -eq 0 ]; then echo "all force checks passed"; else echo "FORCE CHECK FAILED"; fi
exit $status
