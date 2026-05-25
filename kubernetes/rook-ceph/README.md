# Rook-Ceph

Rook-Ceph provides the default Kubernetes StorageClass for the cereal cluster.

The cluster uses one raw SATA SSD on each worker:

| Node | Device | WWID |
|------|--------|------|
| `snap` | `/dev/sda` | `naa.58ce38e801936a51` |
| `crackle` | `/dev/sda` | `naa.58ce38e801936b06` |
| `pop` | `/dev/sda` | `naa.58ce38e801936c18` |

The `ceph-block` StorageClass uses 3 replicas across host failure domains for maximum redundancy on the three-worker cluster. Raw capacity is about 2.88TB; usable replicated capacity is about 960GB before Ceph overhead.

Before rebooting or upgrading storage nodes, verify the Ceph cluster is healthy and handle one node at a time:

```sh
kubectl --namespace rook-ceph get cephcluster rook-ceph
kubectl --namespace rook-ceph wait --timeout=1800s --for=jsonpath='{.status.ceph.health}=HEALTH_OK' cephcluster rook-ceph
```

