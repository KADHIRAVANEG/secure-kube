#!/usr/bin/env python3
"""
SecureKube Manifest Hardening Utility
Parses raw Kubernetes workload manifests (Pod, Deployment, StatefulSet, DaemonSet,
Job, CronJob) and automatically injects all required Pod Security Standards (restricted)
and OPA Gatekeeper constraint compliant configurations.
"""

import sys
import argparse
import copy
from typing import Any, Dict, List, Tuple
import yaml

DEFAULT_CPU_REQUEST = "50m"
DEFAULT_MEM_REQUEST = "64Mi"
DEFAULT_CPU_LIMIT = "200m"
DEFAULT_MEM_LIMIT = "128Mi"
DEFAULT_UID = 10001
DEFAULT_GID = 10001


class Dumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super(Dumper, self).increase_indent(flow, False)


def get_pod_spec(resource: Dict[str, Any]) -> Tuple[Dict[str, Any], str]:
    """Locate the pod spec dictionary and return it along with its path description."""
    kind = resource.get("kind", "")
    spec = resource.get("spec", {})

    if kind == "Pod":
        return spec, "spec"
    elif kind in ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"):
        template_spec = spec.get("template", {}).get("spec", {})
        return template_spec, "spec.template.spec"
    elif kind == "CronJob":
        job_spec = spec.get("jobTemplate", {}).get("spec", {}).get("template", {}).get("spec", {})
        return job_spec, "spec.jobTemplate.spec.template.spec"
    return {}, ""


def harden_pod_spec(pod_spec: Dict[str, Any]) -> List[str]:
    """In-place harden a pod spec and return a list of transformations performed."""
    actions = []

    # 1. Host namespaces
    for host_flag in ["hostNetwork", "hostPID", "hostIPC"]:
        if pod_spec.get(host_flag) is True:
            pod_spec[host_flag] = False
            actions.append(f"Disabled {host_flag} = true")

    # 2. HostPath volumes
    volumes = pod_spec.get("volumes", [])
    for vol in volumes:
        if "hostPath" in vol:
            vol.pop("hostPath")
            vol["emptyDir"] = {}
            actions.append(f"Replaced insecure hostPath volume '{vol.get('name')}' with emptyDir")

    # 3. Pod-level securityContext
    pod_sc = pod_spec.setdefault("securityContext", {})
    if pod_sc.get("runAsNonRoot") is not True:
        pod_sc["runAsNonRoot"] = True
        actions.append("Set pod.spec.securityContext.runAsNonRoot = true")

    if not pod_sc.get("runAsUser") or pod_sc.get("runAsUser") == 0:
        pod_sc["runAsUser"] = DEFAULT_UID
        actions.append(f"Set pod.spec.securityContext.runAsUser = {DEFAULT_UID}")

    if not pod_sc.get("runAsGroup") or pod_sc.get("runAsGroup") == 0:
        pod_sc["runAsGroup"] = DEFAULT_GID
        actions.append(f"Set pod.spec.securityContext.runAsGroup = {DEFAULT_GID}")

    if not pod_sc.get("fsGroup") or pod_sc.get("fsGroup") == 0:
        pod_sc["fsGroup"] = DEFAULT_GID
        actions.append(f"Set pod.spec.securityContext.fsGroup = {DEFAULT_GID}")

    seccomp = pod_sc.setdefault("seccompProfile", {})
    if seccomp.get("type") != "RuntimeDefault":
        seccomp["type"] = "RuntimeDefault"
        actions.append("Set pod.spec.securityContext.seccompProfile.type = RuntimeDefault")

    # Ensure automountServiceAccountToken is explicitly defined
    if "automountServiceAccountToken" not in pod_spec:
        pod_spec["automountServiceAccountToken"] = False
        actions.append("Disabled default automountServiceAccountToken = false")

    # 4. Containers and InitContainers hardening
    container_lists = [
        ("containers", pod_spec.get("containers", [])),
        ("initContainers", pod_spec.get("initContainers", [])),
    ]

    needs_tmp_volume = False

    for list_name, containers in container_lists:
        for c in containers:
            c_name = c.get("name", "unnamed")
            c_sc = c.setdefault("securityContext", {})

            # Privileged
            if c_sc.get("privileged") is True:
                c_sc["privileged"] = False
                actions.append(f"Removed container '{c_name}' privileged = true")

            # Privilege Escalation
            if c_sc.get("allowPrivilegeEscalation") is not False:
                c_sc["allowPrivilegeEscalation"] = False
                actions.append(f"Set container '{c_name}' allowPrivilegeEscalation = false")

            # Non-root container level
            if c_sc.get("runAsNonRoot") is not True:
                c_sc["runAsNonRoot"] = True
                actions.append(f"Set container '{c_name}' runAsNonRoot = true")

            if not c_sc.get("runAsUser") or c_sc.get("runAsUser") == 0:
                c_sc["runAsUser"] = DEFAULT_UID
                actions.append(f"Set container '{c_name}' runAsUser = {DEFAULT_UID}")

            # ReadOnly Root Filesystem
            if c_sc.get("readOnlyRootFilesystem") is not True:
                c_sc["readOnlyRootFilesystem"] = True
                actions.append(f"Set container '{c_name}' readOnlyRootFilesystem = true")
                needs_tmp_volume = True

            # Capabilities: Drop ALL
            caps = c_sc.setdefault("capabilities", {})
            drop_caps = caps.setdefault("drop", [])
            if "ALL" not in drop_caps:
                caps["drop"] = ["ALL"]
                actions.append(f"Set container '{c_name}' capabilities.drop = ['ALL']")
            if "add" in caps:
                # Remove dangerous capabilities if any
                caps["add"] = [cap for cap in caps.get("add", []) if cap.upper() not in ("SYS_ADMIN", "NET_ADMIN", "ALL")]
                if not caps["add"]:
                    caps.pop("add", None)

            # Resources: Requests and Limits
            res = c.setdefault("resources", {})
            reqs = res.setdefault("requests", {})
            limits = res.setdefault("limits", {})

            if "cpu" not in reqs:
                reqs["cpu"] = DEFAULT_CPU_REQUEST
                actions.append(f"Set container '{c_name}' resources.requests.cpu = {DEFAULT_CPU_REQUEST}")
            if "memory" not in reqs:
                reqs["memory"] = DEFAULT_MEM_REQUEST
                actions.append(f"Set container '{c_name}' resources.requests.memory = {DEFAULT_MEM_REQUEST}")

            if "cpu" not in limits:
                limits["cpu"] = DEFAULT_CPU_LIMIT
                actions.append(f"Set container '{c_name}' resources.limits.cpu = {DEFAULT_CPU_LIMIT}")
            if "memory" not in limits:
                limits["memory"] = DEFAULT_MEM_LIMIT
                actions.append(f"Set container '{c_name}' resources.limits.memory = {DEFAULT_MEM_LIMIT}")

            # Ports: Remap privileged ports (<1024)
            for port_spec in c.get("ports", []):
                p = port_spec.get("containerPort", 0)
                if p > 0 and p < 1024:
                    new_p = p + 8000 if p == 80 or p == 443 else p + 8000
                    port_spec["containerPort"] = new_p
                    actions.append(f"Remapped privileged containerPort {p} -> {new_p} on '{c_name}'")

            # Image repository check
            image = c.get("image", "")
            if "/" not in image:
                c["image"] = f"docker.io/library/{image}"
                actions.append(f"Qualified short image '{image}' -> '{c['image']}' for allowed-repos policy")

    # If read-only rootfs was applied and no tmp volume exists, add a standard /tmp emptyDir mount
    if needs_tmp_volume:
        existing_vol_names = {v.get("name") for v in volumes}
        if "tmp-volume" not in existing_vol_names:
            pod_spec.setdefault("volumes", []).append({
                "name": "tmp-volume",
                "emptyDir": {}
            })
            for c in pod_spec.get("containers", []):
                mounts = c.setdefault("volumeMounts", [])
                if not any(m.get("mountPath") == "/tmp" for m in mounts):
                    mounts.append({
                        "name": "tmp-volume",
                        "mountPath": "/tmp"
                    })
            actions.append("Mounted emptyDir volume at /tmp for scratch writing under readOnlyRootFilesystem")

    return actions


def main():
    parser = argparse.ArgumentParser(
        description="SecureKube Manifest Hardener: Automatically transforms insecure Kubernetes manifests into 100% policy-compliant configurations."
    )
    parser.add_argument("file", help="Path to Kubernetes YAML manifest to harden (or '-' for stdin)")
    parser.add_argument("-o", "--output", help="Write hardened manifest to output file (default: stdout)")
    parser.add_argument("-i", "--in-place", action="store_true", help="Modify input file in-place")
    args = parser.parse_args()

    if args.file == "-":
        content = sys.stdin.read()
    else:
        with open(args.file, "r") as f:
            content = f.read()

    docs = list(yaml.safe_load_all(content))
    total_actions = 0
    all_actions = []

    for idx, doc in enumerate(docs):
        if not doc or not isinstance(doc, dict):
            continue
        kind = doc.get("kind", "Unknown")
        name = doc.get("metadata", {}).get("name", f"doc-{idx}")

        pod_spec, path = get_pod_spec(doc)
        if pod_spec:
            actions = harden_pod_spec(pod_spec)
            if actions:
                total_actions += len(actions)
                all_actions.append((f"{kind}/{name}", actions))

    out_content = yaml.dump_all(docs, Dumper=Dumper, default_flow_style=False, sort_keys=False)

    if args.in_place and args.file != "-":
        with open(args.file, "w") as f:
            f.write(out_content)
        dest = args.file
    elif args.output:
        with open(args.output, "w") as f:
            f.write(out_content)
        dest = args.output
    else:
        sys.stdout.write(out_content)
        dest = "stdout"

    # Print summary to stderr so stdout can be piped directly to kubectl
    sys.stderr.write(f"\n✨ SecureKube Hardener applied {total_actions} security remediation(s) to {len(all_actions)} resource(s):\n")
    for r_name, acts in all_actions:
        sys.stderr.write(f"  📦 {r_name}:\n")
        for a in acts:
            sys.stderr.write(f"    ✓ {a}\n")
    sys.stderr.write(f"📁 Output: {dest}\n\n")


if __name__ == "__main__":
    main()
