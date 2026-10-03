# Rook-Ceph

Rook-Ceph provides the default Kubernetes StorageClass for the cereal cluster.

The cluster uses one raw SATA SSD on each worker:

| Node | Device | WWID |
|------|--------|------|
| `snap` | `/dev/sda` | `naa.58ce38e801936a51` |
| `crackle` | `/dev/sda` | `naa.58ce38e801936b06` |
| `pop` | `/dev/sda` | `naa.58ce38e801936c18` |

The `ceph-block` StorageClass uses 3 replicas across host failure domains for maximum redundancy on the three-worker cluster. Raw capacity is about 2.88TB; usable replicated capacity is about 960GB before Ceph overhead.

## S3 object storage

The `ceph-objectstore` CephObjectStore exposes an S3-compatible endpoint through two RADOS Gateway
(RGW) pods, backed by the same three OSDs as `ceph-block` — object data shares the replicated capacity,
it does not get its own disks.

| | |
|---|---|
| Endpoint (in-cluster) | `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80` |
| Endpoint (tailnet) | `https://s3.<tailnet>.ts.net` via `ingress-rgw.yaml` (Tailscale operator, TLS from ts.net) |
| StorageClass for buckets | `ceph-bucket` (`reclaimPolicy: Retain`) |
| Addressing | **path-style** — a `ts.net` name cannot carry the `*.s3.…` wildcard virtual-host style needs |

Both pools are replicated ×3 rather than the chart's default erasure-coded 2+1. EC 2+1 on three hosts
gets `min_size = k+1 = 3`, so a single node reboot would block all object I/O; replication keeps
`min_size 2`. `pg_num_min: "8"` holds the seven new pools to a sane share of the
`mon_max_pg_per_osd` budget.

Provision a bucket by creating an ObjectBucketClaim against `ceph-bucket`; Rook writes the endpoint and
credentials into a ConfigMap and Secret of the same name as the claim. Claims live in this directory
(`obc-*.yaml`) so a wipe and re-bootstrap recreates them; the Retain class means the data behind a
deleted claim survives until someone removes it with `radosgw-admin`.

| Claim | Consumer |
|---|---|
| `leafbit-archive` | Final archives of retired Leafbit services, one prefix per service, uploaded by hand from the MacBook over the tailnet endpoint. Nothing prunes it. |
| `paperclip-backups` | Nightly encrypted snapshots of the Paperclip instance on the MacBook, pushed over the tailnet endpoint by `backup/` in `Leafbit-Ltd/paperclip`. |

Read a claim's credentials from outside the cluster (the values are only ever needed on the client
that owns the bucket; never paste them into this repo):

```sh
kubectl --namespace rook-ceph get configmap paperclip-backups -o jsonpath='{.data.BUCKET_NAME}'
kubectl --namespace rook-ceph get secret paperclip-backups -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
kubectl --namespace rook-ceph get secret paperclip-backups -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
```

The ConfigMap's `BUCKET_HOST` is the in-cluster service name. From the tailnet use
`https://s3.<tailnet>.ts.net` with path-style addressing instead; the same keys work on both.

```sh
kubectl --namespace rook-ceph get cephobjectstore ceph-objectstore
kubectl --namespace rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin bucket stats
```

## Node maintenance

Before rebooting or upgrading storage nodes, verify the Ceph cluster is healthy and handle one node at a time:

```sh
kubectl --namespace rook-ceph get cephcluster rook-ceph
kubectl --namespace rook-ceph wait --timeout=1800s --for=jsonpath='{.status.ceph.health}=HEALTH_OK' cephcluster rook-ceph
```


## Mon write amplification (#74)

`ceph-mon` keeps its ~80 MB RocksDB store under `/var/lib/rook` on the **OS NVMe**, and rewrites it hundreds of times a day (upstream [tracker #63229](https://tracker.ceph.com/issues/63229)). Fixes are applied one at a time through `configOverride` (ceph.conf) in `cluster-helmrelease.yaml` — not `cephConfig`, which mons cannot read before opening their store, with at least 24h of measurement between them.

`mon_rocksdb_options` is read only at mon start. After Flux applies a change, restart the mons one at a time and wait for 3/3 quorum between each:

```sh
for m in b c f; do
  kubectl --namespace rook-ceph rollout restart deploy/rook-ceph-mon-$m
  kubectl --namespace rook-ceph rollout status deploy/rook-ceph-mon-$m
  kubectl --namespace rook-ceph exec deploy/rook-ceph-tools -- ceph quorum_status -f json | jq -r '.quorum_names | join(",")'
done
```

Measure per-node NVMe writes as a 24h increase, never as a short rate (mon writes are bursty), and ignore cAdvisor's `container_fs_writes_bytes_total`:

```promql
sum by (instance) (increase(node_disk_written_bytes_total{device="nvme0n1"}[24h])) / 1e9
```

| step | change | snap GB/day | pop GB/day | crackle GB/day |
|---|---|---|---|---|
| baseline (2026-10-03, crackle out of cluster) | defaults | 87.5 | 90.7 | — |
| 1 | LZ4 on mon RocksDB | | | |
| 2 | double paxos trim thresholds | | | |

## CephX key types (CVE-2025-30156)

Ceph 19.2.6 added `AUTH_INSECURE_*` health checks for the CephX AES-CBC auth bypass. Daemon keys (mon, mgr, osd, rgw, admin) are rotated to `aes256k` by `cephClusterSpec.security.cephx.daemon` in `cluster-helmrelease.yaml`. Every Ceph daemon restarts, and `AUTH_INSECURE_ROTATING_SERVICE_KEY_TYPE` clears 2–3h later on its own. Afterwards the toolbox keeps the old admin key (`RADOS permission denied`) until it's restarted: `kubectl --namespace rook-ceph rollout restart deploy/rook-ceph-tools`. Done 2026-10-03: all 7 krbd PVCs kept reading and writing on kernel 6.18.

CSI and other client keys stay `aes` for now: krbd needs Linux 7.0+ for `aes256k`, and Talos 1.13 ships 6.18. Until then, four warnings are expected and muted. `AUTH_EMERGENCY_CIPHERS_SET` comes from Rook itself, which starts the mons with `--mon-auth-emergency-allowed-ciphers=aes,aes256k` so the `aes` clients keep working. Rook has no field for this, so the mutes are set by hand and stored in the mons:

```sh
for c in AUTH_INSECURE_CLIENT_KEY_TYPE AUTH_INSECURE_KEYS_ALLOWED AUTH_INSECURE_KEYS_CREATABLE AUTH_EMERGENCY_CIPHERS_SET; do
  kubectl --namespace rook-ceph exec deploy/rook-ceph-tools -- ceph health mute "$c" --sticky
done
```

Once all nodes are on kernel 7.0+: set `security.cephx.csi` (`keyGeneration: 2`, `keyType: aes256k`, `keepPriorKeyCountMax: 1`), drain and uncordon each node, then set `security.cephx.allowedCiphers: [aes256k]` and `ceph health unmute` the four checks. See https://rook.io/docs/rook/v1.19/Storage-Configuration/Advanced/cephx-key-rotation/
