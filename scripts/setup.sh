#!/bin/bash
# setup.sh — Controller-side setup (runs before start scripts)
# Verifies dependencies are available.

set -e

echo "=========================================="
echo "Burst Renderer Setup: $(date)"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "Job dir:  ${PW_PARENT_JOB_DIR:-$(pwd)}"

JOB_DIR="${PW_PARENT_JOB_DIR%/}"

# Verify Python
PYTHON_CMD=""
for cmd in python3 python; do
    command -v $cmd &>/dev/null && { PYTHON_CMD=$cmd; break; }
done

if [ -z "${PYTHON_CMD}" ]; then
    echo "[ERROR] Python not found"
    exit 1
fi
echo "Python: ${PYTHON_CMD} ($(${PYTHON_CMD} --version 2>&1))"

# Mark setup complete
touch "${JOB_DIR}/SETUP_COMPLETE"
echo "Setup complete!"
