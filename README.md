# Nature
A repository for tech on the Nature network

#### Talos setup
```
talosctl apply-config --insecure --nodes 10.30.1.50 --file controlplane.yaml
```

```
talosctl apply-config --insecure --nodes 10.30.1.51 --file snap.yaml
talosctl apply-config --insecure --nodes 10.30.1.52 --file crackle.yaml
talosctl apply-config --insecure --nodes 10.30.1.53 --file pop.yaml
```
