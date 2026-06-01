#!/bin/bash
#
# RHOAI 3.x workbench entrypoint.
#
# The RHOAI notebook controller injects the workbench's path prefix in the
# NB_PREFIX environment variable (e.g. /notebook/<namespace>/<name>). Under
# 3.x, workbenches are exposed through Kubernetes Gateway API with path-based
# routing, so the notebook server MUST serve under that prefix and MUST NOT
# strip it from redirects -otherwise the IDE returns "page not found".
#
# Authentication is handled by the platform-injected kube-rbac-proxy in 3.x,
# so the server runs with no token and no password. There is no oauth-proxy
# sidecar in this image (that was the 2.x model).
#
set -euo pipefail

exec jupyter lab \
  --ServerApp.base_url="${NB_PREFIX:-/}" \
  --ServerApp.ip=0.0.0.0 \
  --ServerApp.port=8888 \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.allow_origin='*' \
  --ServerApp.open_browser=False \
  --ServerApp.quit_button=False
