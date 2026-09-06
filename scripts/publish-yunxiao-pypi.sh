#!/usr/bin/env bash
set -euo pipefail

export PIP_DISABLE_PIP_VERSION_CHECK="${PIP_DISABLE_PIP_VERSION_CHECK:-1}"
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"
export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-mirrors.aliyun.com}"
export TWINE_REPOSITORY_URL="${TWINE_REPOSITORY_URL:-https://packages.aliyun.com/63d476f8d14a7f379aa798da/pypi/lyriktrip}"
export TWINE_USERNAME="${TWINE_USERNAME:-${PYPI_USERNAME:-63c537efbb097da55ff323e3}}"
export TWINE_PASSWORD="${TWINE_PASSWORD:-${PYPI_PASSWORD:-}}"

if [[ -z "${TWINE_PASSWORD}" ]]; then
  echo "TWINE_PASSWORD is not configured; skip package publish." >&2
  exit 1
fi

if ! compgen -G "dist/*" >/dev/null; then
  echo "dist/ is empty. Run 'python -m build' or 'uv build' first." >&2
  exit 1
fi

command -v uv >/dev/null || {
  echo "Missing uv; required for temporary twine execution." >&2
  exit 1
}

package_meta="$(
  python3 - <<'PY'
from pathlib import Path
import tomllib

project = tomllib.loads(Path("pyproject.toml").read_text())["project"]
print(project["name"])
print(project["version"])
PY
)"

package_name="${package_meta%%$'\n'*}"
package_version="${package_meta#*$'\n'}"

auth_index_url="$(
  python3 - "$TWINE_REPOSITORY_URL" "$TWINE_USERNAME" "$TWINE_PASSWORD" <<'PY'
import sys
from urllib.parse import quote, urlsplit, urlunsplit

raw_url, username, password = sys.argv[1:4]
parts = urlsplit(raw_url)
netloc = f"{quote(username, safe='')}:{quote(password, safe='')}@{parts.hostname}"
if parts.port:
    netloc += f":{parts.port}"
print(urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment)))
PY
)"

check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT

if python3 -m pip download \
  --quiet \
  --no-deps \
  --dest "$check_dir" \
  --trusted-host packages.aliyun.com \
  --index-url "$auth_index_url" \
  --extra-index-url https://mirrors.aliyun.com/pypi/simple \
  "${package_name}==${package_version}" >/dev/null 2>&1; then
  echo "${package_name}==${package_version} already exists in Yunxiao Packages; skip package publish."
  exit 0
fi

echo "${package_name}==${package_version} is not present in Yunxiao Packages yet; publishing dist/*."
uv run --with twine python -m twine check dist/*
uv run --with twine python -m twine upload dist/*
