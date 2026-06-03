# Migrating Red Hat OpenShift AI 2.25 to 3.3 — Showroom

A hands-on workshop that walks an OpenShift admin through an in-place migration of a **production-shaped** Red Hat OpenShift AI cluster from **2.25 to 3.3**.

The 2.x → 3.x jump is a migration, not a routine version bump: the routing layer moves from OpenShift Routes to **Kubernetes Gateway API**, authentication moves from `oauth-proxy` to `kube-rbac-proxy`, and several components your workloads currently depend on are **removed** — Serverless model serving, ModelMesh, embedded Kueue, and CodeFlare. Workloads have to be migrated off them, in the right order, before the components can be disabled.

## What this tutorial covers

The lab cluster starts in a realistic pre-migration state: KServe Serverless ISVCs, a ModelMesh model, a custom (BYON) workbench image built for the 2.x auth model, sample workbenches, and a Data Science Pipelines application.

| Module | What you'll do |
|---|---|
| **1. Test baseline** | Exercise every user-facing workload and capture a snapshot to diff against later. |
| **2. Assess** | Run the `rhai-cli` assessment and interpret its findings. |
| **3. Convert serving** | Convert Serverless ISVCs to RawDeployment; migrate the ModelMesh model to KServe. |
| **4. Remediate platform** | Mark removed components `Removed`, patch the model-serving ConfigMap, drop the Service Mesh dependency, uninstall 2.x operators. |
| **5. Workbench images** | Rebuild and re-register the custom workbench image for 3.x; stop every workbench. |
| **6. Upgrade** | Drive the OLM upgrade through the migration channel to 3.3, then move to stable. |
| **7. Verify** | Confirm the platform, the converted models, the schema/HardwareProfiles, and the new auth model. |
| **8. Re-test** | Re-run every Module 1 test against the migrated endpoints and diff the baseline. |

The content lives in [content/modules/ROOT/pages/](content/modules/ROOT/pages/); supporting assets (e.g. the rebuilt workbench image for Module 5) are in [examples/](examples/).

## Run locally

The fastest loop for editing content is the [antora-viewer](https://github.com/juliaaano/antora-viewer) container — it rebuilds on save and serves the site on `http://localhost:8080`:

```sh
podman run --rm --name antora \
  -v $PWD:/antora \
  -p 8080:8080 \
  -it ghcr.io/juliaaano/antora-viewer
```

Docker works too — swap `podman` for `docker`.

To produce a static build without the live viewer:

```sh
npx antora default-site.yml
```

The output is written to [www/](www/) and can be served by any static web server.

## Deploy on OpenShift

The site is deployed using the RHPDS [Showroom](https://github.com/rhpds/showroom) Helm chart, which builds the Antora site and serves it alongside a workshop terminal panel.

> **Two gotchas in chart 0.1.9** (it's built for the RHPDS deployer / agnosticd, not standalone use):
>
> 1. The chart computes its target namespace as `general.namespace`-`general.guid`-`general.catalogItem` and writes resources there regardless of `--namespace`. The namespace must already exist; `--create-namespace` only creates the release namespace, not the computed one. The three `general.*` values, hyphenated and lowercased, must equal the namespace you create.
> 2. `content.repoUrl` / `content.repoRevision` are declared in `values.yaml` but the content Deployment template ignores them and hardcodes the upstream ARO ILT repo. You have to patch `GIT_REPO_URL` on the running Deployment after `helm install`. Only the `main` branch is supported (no revision override is wired into the content image).

```sh
NS=showroom-rhoaimig-prod
oc new-project $NS || oc project $NS

helm upgrade --install rhoai-migrations-showroom \
  oci://quay.io/rhpds/showroom --version 0.1.9 \
  --namespace $NS \
  --set general.namespace=showroom \
  --set general.guid=rhoaimig \
  --set general.catalogItem=prod \
  --set deployer.domain=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')

# Point the content pod at this repo (works around the chart bug)
oc -n $NS set env deployment/showroom-content \
  GIT_REPO_URL=https://github.com/rh-aiservices-bu/rhoai-migrations-showroom.git
oc -n $NS rollout restart deployment/showroom-content
```

Once the pods are `Ready`, get the route:

```sh
oc get route -n $NS -o jsonpath='{.items[0].spec.host}'
```

> **Cluster parameters:** the workshop expects values like `openshift_console_url`, `openshift_cluster_admin_username`, `openshift_cluster_admin_password`, and `openshift_cluster_ingress_domain` (referenced in [content/modules/ROOT/pages/index.adoc](content/modules/ROOT/pages/index.adoc)) to be supplied by the surrounding RHPDS catalog item. When running standalone, pass them via additional `--set` flags or render the AsciiDoc with substitutions handled out-of-band.

## Layout

```
content/           Antora content sources (modules, pages, nav)
examples/          Supporting assets referenced by the modules
default-site.yml   Antora playbook
ui-config.yml      UI bundle configuration
www/               Built site output (gitignored in normal use)
```
