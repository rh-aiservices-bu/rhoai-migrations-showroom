# Custom workbench image — rebuilt for RHOAI 3.x

This directory is the reference artifact for Module 4 of the migration workshop. It contains the source for the pre-built, 3.x-ready custom workbench image the lab swaps in (`gw-workbench-image` in `content/antora.yml`).

It exists so learners can see *exactly* what changes when you rebuild a custom (BYON) workbench image to work under RHOAI 3.x.

## What changed from the 2.x image

The 2.x BYON image was the upstream community SciPy notebook (`quay.io/jupyter/scipy-notebook:lab-4.2.5`). It made two assumptions that RHOAI 3.x breaks:

| Assumption (2.x) | Reality (3.x) | Fix in this image |
|---|---|---|
| An `oauth-proxy` sidecar handles auth | The platform injects `kube-rbac-proxy` | No oauth-proxy in the image; the server runs token-less and password-less |
| Exposed via an OpenShift Route at the host root | Exposed via Gateway API under a path prefix (`NB_PREFIX`) | Entrypoint serves Jupyter under `--ServerApp.base_url="${NB_PREFIX}"` |

## Files

- **`Containerfile`** — rebuilds the image: layers the RHOAI-aware entrypoint on the community base, removes the oauth-proxy assumption, and makes the workdir tolerant of OpenShift's arbitrary UID.
- **`start-rhoai-notebook.sh`** — the entrypoint. Serves Jupyter under `NB_PREFIX` with no token/password (auth is the platform's job in 3.x).

## Build and push

```sh
podman build -t quay.io/<org>/custom-scipy-notebook-gw:3.x -f Containerfile .
podman push  quay.io/<org>/custom-scipy-notebook-gw:3.x
```

Then update the lab's image reference in one place — `content/antora.yml`:

```yaml
gw-workbench-image: "quay.io/<org>/custom-scipy-notebook-gw:3.x"
```

Every reference in Module 4 picks up the new value automatically.

## How the lab consumes it

Module 4 re-registers the cluster's `custom-scipy-notebook` ImageStream to point at this image:

```sh
oc tag <gw-workbench-image> custom-scipy-notebook:3.x \
  -n redhat-ods-applications --reference-policy=local
```

## Notes

- **Arbitrary UID:** OpenShift runs containers with a random UID by default. The `Containerfile` makes `/home/jovyan` group-writable so the server runs as any UID in the root group. Alternatively, grant the workbench ServiceAccount the `anyuid` SCC (the workshop's `custom` workbench already has an `anyuid` RoleBinding).
- **Private registry:** if you push to a private repo, add a pull secret to the `redhat-ods-applications` namespace so the workbench pod can pull the image.
- **Production base:** for a fully supported image, rebase on a Red Hat UBI9 + Python base rather than the community image. Layering on the community base (as here) is the pragmatic path and is sufficient for the workshop.
- **NGINX-based images (code-server, RStudio):** those need extra care — keep `NB_PREFIX` in every `Location:` redirect header, and revert any `/api` inline rewrite to a 302 redirect to avoid a `SCRIPT_FILENAME` 403. Jupyter-based images (like this one) honor `NB_PREFIX` natively and are simpler.
