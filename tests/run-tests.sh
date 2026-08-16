#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "${script_dir}/.." && pwd)"
image_name="files-archive-tests"

docker build -f "${project_root}/tests/Dockerfile" -t "${image_name}" "${project_root}/tests"
docker run --rm \
  -v "${project_root}:/work" \
  -w /work \
  "${image_name}" \
  pwsh -NoProfile -ExecutionPolicy Bypass -File /work/tests/run-tests.ps1
