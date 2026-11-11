#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
swift_flags=(-swift-version 5 -module-cache-path build/checks/ModuleCache)
# Compiler helpers already run inside the calling tool's isolation in some agents.
# This optional flag is for those environments and does not change the app project.
if [[ "${AVPLEARN_RESTRICTED_BUILD:-0}" == "1" ]]; then
  swift_flags+=(-Xfrontend -disable-sandbox)
fi
xcrun swiftc "${swift_flags[@]}" LearningTypes.swift Curriculum.swift LearningStore.swift Tests/LearningStoreChecks.swift -o build/checks/learning
build/checks/learning
xcrun swiftc "${swift_flags[@]}" LabModels.swift Tests/CircuitChecks.swift -o build/checks/circuits
build/checks/circuits
xcrun swiftc "${swift_flags[@]}" CADModels.swift CADTemplates.swift Tests/CADChecks.swift -o build/checks/cad
build/checks/cad
xcrun swiftc "${swift_flags[@]}" MechanicsModel.swift Tests/MechanicsChecks.swift -o build/checks/mechanics
build/checks/mechanics
xcrun swiftc "${swift_flags[@]}" CADModels.swift CADTemplates.swift CADMeshLibrary.swift CADExport.swift Tests/CADGeometryChecks.swift -o build/checks/geometry
rm -f build/checks/cad-*.obj
build/checks/geometry
python3 Tests/check_obj_geometry.py build/checks/cad-actual-*.obj build/checks/cad-review-*.obj > build/checks/obj-audit.txt
grep '^PASS' build/checks/obj-audit.txt
