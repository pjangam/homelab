# Kubernetes (k3s / minikube) instead of Docker Compose
**Status:** Closed

**Why:** asked 2026-10-30 whether k8s, k3s or minikube makes sense here, or whether Docker Compose is still the right tool.
**Outcome:** closed 2026-10-30: stay on Docker Compose. User may revisit in 2027. The reasoning, so it does not have to be redone:
- **Kubernetes solves problems this setup does not have.** Its value is scheduling across many nodes, moving work off a dead node, zero-downtime rolling updates and many people deploying to one cluster. Here one box (xero) runs nearly everything; the Pi has a few fixed jobs; the ESP32s and Macs are not container hosts.
- **Cost on the N5105.** Even k3s keeps a control plane running: roughly 0.5-1GB RAM and a steady few percent CPU, around the clock, on a CPU whose heat is already managed (Immich load guard, ML capped at 2 cores).
- **The setup leans on the host.** 9 services use `network_mode: host` (HA, Pi-hole on :53, mDNS for ESPHome and friends), ZFS datasets are bind-mounted, the iGPU is passed through for VAAPI, cAdvisor is privileged, and audio runs as systemd --user services. Each is one line in Compose and a workaround in k8s (hostNetwork, hostPath, device plugins).
- **Operability.** The user now mostly directs and operates while Claude writes the code; one compose file plus scripts with usage headers stays readable and checkable. k8s adds a layer (pods, services, ingress, certs) between them and every fault.
- **Minikube is a developer sandbox**, a cluster inside a VM or container, not meant to run real services long-term. Ruled out outright.
- **What Compose lacks is already covered cheaper:** `restart: always` + healthchecks, the healthcheck script + ntfy, everything in git, the Pi's secondary Pi-hole for DNS failover. Real failover for more would need a second server - a hardware question, not an orchestration one.

**What would change the answer:** a second always-on server worth spreading load across, or wanting to learn k8s. For learning, do it as its own project (k3s on the Lenovo Flex or a VM on the 2019 MacBook) and never move HA, DNS or photos onto it.

#### Log
- 2026-10-30: asked and answered; closed, revisit maybe in 2027.
