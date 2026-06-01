# Custom workbench image — RHOAI 2.x (before-upgrade)

This is the *before* image in the workshop — the legacy custom workbench the cluster starts with. It represents a typical customer BYON: the community Jupyter SciPy notebook with a couple of data-science packages layered on top. It works under RHOAI 2.x and breaks under 3.x.

## What this image is

| | |
|---|---|
| Base | `quay.io/jupyter/scipy-notebook:lab-4.2.5` |
| Layered packages | `mlflow~=2.9`, `onnxruntime~=1.17` |
| Entrypoint | Inherited from base (no NB_PREFIX handling) |
| RHOAI 2.x | Works (oauth-proxy sidecar + Route at host root) |
| RHOAI 3.x | **Breaks** (no oauth-proxy, Gateway API path-based routing) |

## Why it breaks under 3.x

The workshop's Module 4 explains in detail. Summary: the image assumes oauth-proxy will be injected and Jupyter will be served at the host root via an OpenShift Route. Under 3.x both assumptions fail.

## How to build and push

See [../README.md](../README.md) for the consolidated build-and-push guide covering both this image and the 3.x rebuild ([../custom-workbench-gw/](../custom-workbench-gw/)).

## Keep in sync with the 3.x rebuild

If you change the `FROM` or the `pip install` line here, mirror the same change in [../custom-workbench-gw/Containerfile](../custom-workbench-gw/Containerfile). The workshop's story is "same image, rebuilt for 3.x" — if the two drift, the comparison no longer holds.
