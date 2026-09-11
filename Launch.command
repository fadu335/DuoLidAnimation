#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d build/DuoLidAnimation.app ]]; then ./Utilities/build.sh; fi
open build/DuoLidAnimation.app
