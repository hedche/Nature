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

