#!/bin/bash
set -euo pipefail
source_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$source_directory/environment.sh"
musicfox_qt6_environment "${MUSICFOX_QT6_PREFIX:-$source_directory/.sdk/usr}"
export QT_MEDIA_BACKEND="${MUSICFOX_TEST_MEDIA_BACKEND:-ffmpeg}"
python3 -m unittest discover -s "$source_directory/tests" -p 'test_*.py'
ctest --test-dir "${MUSICFOX_BUILD_DIR:-$source_directory/build}" --output-on-failure
