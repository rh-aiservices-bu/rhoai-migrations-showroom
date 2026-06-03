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

> **Always pass `--platform linux/amd64`.** The lab clusters run on amd64 nodes. If you build on Apple Silicon (or any arm64 host) without this flag, podman produces an arm64 image and the workbench pod fails to start with:
>
> ```
> exec container process `/usr/bin/tini`: Exec format error
> ```
>
> The flag forces podman to emulate amd64 via QEMU so the resulting image runs on the cluster regardless of your build host. (See [Multi-arch](#multi-arch-optional) below if you also want a native arm64 variant for local dev.)

## 2. Build and push the 2.x image (before-upgrade)

```sh
cd examples/custom-workbench-2x

podman build \
  --platform linux/amd64 \
  -t quay.io/hayesphilip/rhoai-workbench-2x:lab-4.2.5 \
  -f Containerfile .

podman push quay.io/hayesphilip/rhoai-workbench-2x:lab-4.2.5
```

The tag `lab-4.2.5` mirrors the upstream base tag so you can tell at a glance what version of the SciPy notebook it's based on. You can also push a `:latest` if you want a floating tag.

## 3. Build and push the 3.x rebuild (after-upgrade)

```sh
cd examples/custom-workbench-gw

podman build \
  --platform linux/amd64 \
  -t quay.io/hayesphilip/rhoai-workbench-gw:3.x \
  -f Containerfile .

podman push quay.io/hayesphilip/rhoai-workbench-gw:3.x
```

The `:3.x` tag signals this image is compatible with the 3.x line broadly. If you maintain it for a specific minor release later, tag accordingly (`:3.3`, `:3.4`, etc.).

## 4. Smoke-test the pushed images

```sh
podman pull --platform linux/amd64 quay.io/<org>/rhoai-workbench-2x:lab-4.2.5
podman pull --platform linux/amd64 quay.io/<org>/rhoai-workbench-gw:3.x

# Confirm each manifest is amd64 — should print "amd64".
podman inspect quay.io/<org>/rhoai-workbench-2x:lab-4.2.5 --format '{{.Architecture}}'
podman inspect quay.io/<org>/rhoai-workbench-gw:3.x       --format '{{.Architecture}}'
```

Both should pull without auth. If you get `unauthorized: access to the requested resource is not authorized`, the quay.io repo is still private — flip it to public in the repo settings.

If `Architecture` comes back as `arm64`, you built on Apple Silicon without `--platform linux/amd64` — rebuild with the flag and re-push, otherwise the workbench pod will crash with `Exec format error`.

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

The instructions above produce a single amd64 image, which is all the lab cluster needs. If you *also* want a native arm64 variant for local dev on Apple Silicon (faster iteration, no QEMU emulation), publish a multi-arch manifest:

```sh
podman build --platform linux/amd64,linux/arm64 --manifest \
  quay.io/<org>/rhoai-workbench-2x:lab-4.2.5 -f Containerfile .
podman manifest push quay.io/<org>/rhoai-workbench-2x:lab-4.2.5
```

(Same shape for the `-gw` image.) When pulled from the amd64 cluster, podman picks the amd64 variant automatically; when pulled locally on arm64, it picks arm64.

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
