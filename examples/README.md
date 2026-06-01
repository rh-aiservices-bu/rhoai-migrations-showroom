# Building and pushing the two custom workbench images

The workshop uses two custom workbench images that you build and push to quay.io:

| Image | Used | Purpose |
|---|---|---|
| **`custom-workbench-2x`** | *Before* the upgrade (workshop starting state) | Represents a typical customer 2.x BYON image — community Jupyter base + a couple of layered packages. Works under RHOAI 2.x (oauth-proxy sidecar + Route at host root). Does NOT work under 3.x. |
| **`custom-workbench-gw`** | *After* the upgrade (the rebuild Module 4 swaps in) | The same image rebuilt for RHOAI 3.x — kube-rbac-proxy compatible, NB_PREFIX-aware entrypoint, no oauth-proxy assumptions. |

Both are based on `quay.io/jupyter/scipy-notebook:lab-4.2.5` so the only meaningful difference is the 3.x compatibility layer.

The Containerfile sources live in the two sibling directories:

```
examples/
├── custom-workbench-2x/
│   └── Containerfile
├── custom-workbench-gw/
│   ├── Containerfile
│   └── start-rhoai-notebook.sh   ← NB_PREFIX-aware entrypoint
└── README.md                     ← you are here
```

---

## Prerequisites

* A quay.io account and an organization or username you can push to (referred to below as `<org>`).
* `podman` (or `docker`) installed locally.
* Logged in to quay.io:

  ```sh
  podman login quay.io
  ```

## 1. Create the two quay.io repositories

In the quay.io UI, create two **public** repositories under your org:

* `<org>/rhoai-workbench-2x`
* `<org>/rhoai-workbench-gw`

(Public so the lab cluster can pull without configuring a pull secret. If you keep them private, add a pull secret to the workbench namespaces — see *Private registries* below.)

## 2. Build and push the 2.x image (before-upgrade)

```sh
cd examples/custom-workbench-2x

podman build \
  -t quay.io/<org>/rhoai-workbench-2x:lab-4.2.5 \
  -f Containerfile .

podman push quay.io/<org>/rhoai-workbench-2x:lab-4.2.5
```

The tag `lab-4.2.5` mirrors the upstream base tag so you can tell at a glance what version of the SciPy notebook it's based on. You can also push a `:latest` if you want a floating tag.

## 3. Build and push the 3.x rebuild (after-upgrade)

```sh
cd examples/custom-workbench-gw

podman build \
  -t quay.io/<org>/rhoai-workbench-gw:3.x \
  -f Containerfile .

podman push quay.io/<org>/rhoai-workbench-gw:3.x
```

The `:3.x` tag signals this image is compatible with the 3.x line broadly. If you maintain it for a specific minor release later, tag accordingly (`:3.3`, `:3.4`, etc.).

## 4. Smoke-test the pushed images

```sh
podman pull quay.io/<org>/rhoai-workbench-2x:lab-4.2.5
podman pull quay.io/<org>/rhoai-workbench-gw:3.x
```

Both should pull without auth. If you get `unauthorized: access to the requested resource is not authorized`, the quay.io repo is still private — flip it to public in the repo settings.

## 5. Wire the new image URLs into the workshop

Update [`content/antora.yml`](../content/antora.yml) so the lab uses the images you just pushed. There are two attributes:

```yaml
asciidoc:
  attributes:
    # Used in Module 4 — the legacy 2.x image the BYON ImageStream initially points at.
    legacy-workbench-image: "quay.io/<org>/rhoai-workbench-2x:lab-4.2.5"

    # Used in Module 4 — the rebuilt 3.x image the learner swaps in.
    gw-workbench-image: "quay.io/<org>/rhoai-workbench-gw:3.x"
```

Once those are committed, every reference in Module 4 picks up the new values automatically — both the "before" image the cluster starts with and the "after" image the learner re-registers the ImageStream to.

## 6. Update the install sample (one-time)

The starting cluster registers the 2.x image as a BYON ImageStream. Update [rhoai-2254-install/30-samples/byon-imagestream/imagestream.yaml](../../rhoai-2254-install/30-samples/byon-imagestream/imagestream.yaml) so its `from.kind: DockerImage` `name:` points at `quay.io/<org>/rhoai-workbench-2x:lab-4.2.5` (replacing the upstream community URL the sample currently uses). Future `install.sh` runs will register your 2.x image.

---

## Multi-arch (optional)

If you want both `amd64` and `arm64` (typical for the OpenShift workbench node pool plus Apple Silicon dev):

```sh
podman build --platform linux/amd64,linux/arm64 --manifest \
  quay.io/<org>/rhoai-workbench-2x:lab-4.2.5 -f Containerfile .
podman manifest push quay.io/<org>/rhoai-workbench-2x:lab-4.2.5
```

(Same shape for the `-gw` image.) Most lab clusters are amd64-only, so single-arch is fine unless you have a specific reason.

## Private registries

If you keep the repos private, the workbench ServiceAccount needs a pull secret:

```sh
oc -n redhat-ods-applications create secret docker-registry quay-pull \
  --docker-server=quay.io \
  --docker-username=<user> \
  --docker-password=<robot-token>

oc -n redhat-ods-applications secrets link default quay-pull --for=pull
```

Repeat for the workbench namespaces (the install creates `workbenches-regular` and `workbenches-hwp` and `rhods-notebooks`).

## Re-building when the upstream base changes

If the upstream `quay.io/jupyter/scipy-notebook` releases a new tag and you want to refresh:

1. Update `FROM` in **both** Containerfiles (keep them in sync).
2. Update the layered package versions in both (keep them identical — the whole point is "same packages, rebuilt for 3.x").
3. Re-tag (e.g. `lab-4.3.0` / `3.x-lab-4.3.0`) and push.
4. Update the two attributes in `content/antora.yml`.

The "same packages, different compatibility layer" property is what the workshop hinges on — don't let the two Containerfiles drift in package contents or the rebuild story falls apart.
