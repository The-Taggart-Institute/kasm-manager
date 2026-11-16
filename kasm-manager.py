#!/usr/bin/env python3
from random import choice
from secrets import token_urlsafe
from datetime import datetime, timezone
import base64
import json
import os
import time

import click
from dotenv import load_dotenv
import kubernetes
from kubernetes import client as k8s
from kubernetes.client.exceptions import ApiException
from rich import print as rprint
from rich.live import Live
from rich.spinner import Spinner
from rich.table import Table
from rich.text import Text

# Configuration
# ==============
# Values are read from the environment, falling back to a `.env` file in the
# working directory. Only KASM_DOMAIN is required; everything else has a
# working default. See .env.example for documentation.
load_dotenv()

DOMAIN = os.environ.get("KASM_DOMAIN", "")
NAMESPACE = os.environ.get("KASM_NAMESPACE", "kasm")
ID_START = int(os.environ.get("KASM_ID_START", 6901))   # logical instance IDs, no longer real ports
ID_END = int(os.environ.get("KASM_ID_END", 7000))
IDS = list(range(ID_START, ID_END))
PASSWORD_LEN = int(os.environ.get("KASM_PASSWORD_LEN", 20))
MAX_SESSION_TIME = int(os.environ.get("KASM_MAX_SESSION_TIME", 7200))
TLS_SECRET = os.environ.get("KASM_TLS_SECRET", "kasm-wildcard-tls")
LABEL_SELECTOR = os.environ.get("KASM_LABEL_SELECTOR", "app=kasm")
IMAGES = {
    key.removeprefix("KASM_IMAGE_").lower(): value
    for key, value in os.environ.items()
    if key.startswith("KASM_IMAGE_")
} or {"terminal": "taggarttech/tti-kasm-terminal:latest",
      "kali": "taggarttech/tti-kasm-kali:latest"}
# END CONFIGURATION
# =================

if not DOMAIN:
    rprint("[bold red][!] KASM_DOMAIN is not set. Add it to a .env file or export it, e.g. KASM_DOMAIN=lab.example.com[/bold red]")
    raise SystemExit(1)
# END CONFIGURATION
# =================

"""
`kasm-manager create`
    1. Pick an unused logical instance ID
    2. Generate a random password, stored in a Kubernetes Secret
    3. Create a Deployment (port 6901, VNC_PW env, 2 CPU / 2 Gi limits)
    4. Create a ClusterIP Service exposing port 6901
    5. Create an Ingress routing kasm-<id>.<KASM_DOMAIN> to the Service

`kasm-manager destroy <ID>`
    Idempotently deletes the Ingress, Service, Deployment, and Secret.
    A 404 on any object is not an error.

`kasm-manager list`
    Lists all labeled instances with image, age, and URL.

`kasm-manager inspect <ID>`
    Prints the composed instance details as indented JSON.

`kasm-manager prune`
    Destroys every instance older than MAX_SESSION_TIME.
"""


def kube() -> tuple[k8s.CoreV1Api, k8s.AppsV1Api, k8s.NetworkingV1Api]:
    """
    Returns (core, apps, net) API clients, loading kubeconfig or falling
    back to in-cluster config (for a future in-cluster web backend).
    """
    try:
        kubernetes.config.load_kube_config()
    except kubernetes.config.config_exception.ConfigException:
        kubernetes.config.load_incluster_config()
    return k8s.CoreV1Api(), k8s.AppsV1Api(), k8s.NetworkingV1Api()


def get_password() -> str:
    return token_urlsafe(PASSWORD_LEN)


def instance_url(id: int) -> str:
    return f"https://kasm-{id}.{DOMAIN}" if DOMAIN else ""


def instance_objects(id: int) -> dict | None:
    """
    Composes instance details from the Secret + Deployment.
    Returns None when the deployment does not exist.
    """
    core, apps, _ = kube()
    try:
        deployment = apps.read_namespaced_deployment(f"kasm-{id}", NAMESPACE)
    except ApiException as e:
        if e.status == 404:
            return None
        raise
    try:
        password = base64.b64decode(
            core.read_namespaced_secret(f"kasm-{id}", NAMESPACE).data["password"]
        ).decode("utf-8")
    except ApiException:
        password = None
    return {
        "name": deployment.metadata.name,
        "id": id,
        "image": deployment.metadata.labels.get("kasm-image"),
        "created": deployment.metadata.creation_timestamp.isoformat(),
        "password": password,
        "url": instance_url(id),
    }


def delete_instance(id: int):
    """
    Deletes the Ingress, Service, Deployment, and Secret for the given ID.
    404 on any object is fine — fully idempotent.
    """
    core, apps, net = kube()
    target_name = f"kasm-{id}"
    for kind, delete in [
        ("Ingress", net.delete_namespaced_ingress),
        ("Service", core.delete_namespaced_service),
        ("Deployment", apps.delete_namespaced_deployment),
        ("Secret", core.delete_namespaced_secret),
    ]:
        try:
            delete(target_name, NAMESPACE)
            rprint(f"[bold red][!] Removed {kind} {target_name}[/bold red]")
        except ApiException as e:
            if e.status != 404:
                raise


def wait_for_instance(id: int, timeout: int = 600) -> bool:
    """
    Polls the instance pod until it is Ready, fails, or the timeout elapses.
    Returns True when Ready. Prints the failure reason otherwise.
    """
    core, apps, _ = kube()
    name = f"kasm-{id}"
    deadline = time.monotonic() + timeout
    phase = Text("waiting for the API server")

    with Live(Spinner("dots", text=phase), refresh_per_second=4) as live:
        while time.monotonic() < deadline:
            # Deployment-level status
            try:
                deployment = apps.read_namespaced_deployment(name, NAMESPACE)
            except ApiException:
                time.sleep(1)
                continue
            conditions = {c.type: c for c in deployment.status.conditions or []}
            replicas = deployment.status.ready_replicas or 0

            if replicas >= 1:
                return True

            # Pod-level status for phase reporting
            pods = core.list_namespaced_pod(
                NAMESPACE, label_selector=f"kasm-id={id}"
            )
            detail = ""
            for pod in pods.items:
                if pod.status.phase == "Pending":
                    for c in pod.status.container_statuses or []:
                        if c.state.waiting:
                            detail = c.state.waiting.reason or ""
                elif pod.status.phase in ("Failed", "Unknown"):
                    live.update(Text(""))
                    rprint(f"[bold red][!] Pod {pod.metadata.name} entered {pod.status.phase}[/bold red]")
                    _print_pod_failure(pod)
                    return False
                for c in pod.status.container_statuses or []:
                    if c.state.waiting and "CrashLoopBackOff" in (c.state.waiting.reason or ""):
                        live.update(Text(""))
                        rprint(f"[bold red][!] Container is crash-looping (CrashLoopBackOff)[/bold red]")
                        _print_pod_failure(pod)
                        return False
                    if c.state.waiting:
                        detail = c.state.waiting.reason or ""

            phase = Text(detail or deployment_progress(conditions))
            live.update(Spinner("dots", text=phase))
            time.sleep(2)

    rprint(f"[bold red][!] Timed out waiting for {name} to become ready[/bold red]")
    return False


def deployment_progress(conditions: dict) -> str:
    """Human-readable summary of where the deployment is in its rollout."""
    if "Progressing" in conditions:
        reason = conditions["Progressing"].reason
        if reason == "ReplicaSetUpdated":
            return "starting the workspace container"
        if reason == "MinimumReplicasUnavailable" or "Available" not in conditions:
            return "scheduling the pod"
    if "Available" in conditions and not (conditions["Available"].status or False):
        return "waiting for the container to start"
    return "rolling out"


def _print_pod_failure(pod):
    """Prints the last events and container termination reasons for a failed pod."""
    core, _, _ = kube()
    for status in pod.status.container_statuses or []:
        term = status.state.terminated
        if term:
            rprint(f"[bold red][!] Container exited: {term.reason} (exit code {term.exit_code})[/bold red]")
            if term.message:
                rprint(f"[bold red]    {term.message}[/bold red]")
    try:
        events = core.list_namespaced_event(
            NAMESPACE,
            field_selector=f"involvedObject.name={pod.metadata.name}",
        )
        for ev in events.items[-5:]:
            rprint(f"[yellow]    {ev.reason}: {ev.message}[/yellow]")
    except ApiException:
        pass


@click.group()
def cli():
    pass


@cli.command(help="Creates a new Kasm Instance")
@click.option("-i", "--image", default="terminal", show_default=True, help="Image type")
def create(image):
    """
    Launches a new Kasm Instance.
    """

    # Retrieve image name
    try:
        image_name = IMAGES[image]
    except KeyError:
        rprint(f"[bold red][!] No such image type: {image}[/bold red]")
        return

    core, apps, net = kube()

    # Guarantees we only use available IDs
    deployments = apps.list_namespaced_deployment(NAMESPACE, label_selector=LABEL_SELECTOR)
    used_ids = [int(d.metadata.labels["kasm-id"]) for d in deployments.items]
    available_ids = [i for i in IDS if i not in used_ids]
    if not available_ids:
        rprint("[bold red][!] No instance IDs available[/bold red]")
        return

    new_id = choice(available_ids)
    new_name = f"kasm-{new_id}"
    new_pass = get_password()
    labels = {"app": "kasm", "kasm-id": str(new_id), "kasm-image": image}

    rprint(f"[bold blue][+] Creating Kasm Instance {new_name}![/bold blue]")

    # Secret holding the VNC password
    core.create_namespaced_secret(
        NAMESPACE,
        k8s.V1Secret(
            metadata=k8s.V1ObjectMeta(name=new_name, labels=labels),
            string_data={"password": new_pass},
        ),
    )

    # Deployment running the workspace container
    apps.create_namespaced_deployment(
        NAMESPACE,
        k8s.V1Deployment(
            metadata=k8s.V1ObjectMeta(name=new_name, labels=labels),
            spec=k8s.V1DeploymentSpec(
                replicas=1,
                selector=k8s.V1LabelSelector(match_labels={"kasm-id": str(new_id)}),
                template=k8s.V1PodTemplateSpec(
                    metadata=k8s.V1ObjectMeta(name=new_name, labels=labels),
                    spec=k8s.V1PodSpec(
                        containers=[
                            k8s.V1Container(
                                name=new_name,
                                image=image_name,
                                ports=[k8s.V1ContainerPort(container_port=6901)],
                                env=[k8s.V1EnvVar(name="VNC_PW", value=new_pass)],
                                resources=k8s.V1ResourceRequirements(
                                    limits={"cpu": "2", "memory": "2Gi"}
                                ),
                                image_pull_policy="IfNotPresent",
                            )
                        ]
                    ),
                ),
            ),
        ),
    )

    # ClusterIP Service for the workspace
    core.create_namespaced_service(
        NAMESPACE,
        k8s.V1Service(
            metadata=k8s.V1ObjectMeta(name=new_name, labels=labels),
            spec=k8s.V1ServiceSpec(
                type="ClusterIP",
                selector={"kasm-id": str(new_id)},
                ports=[k8s.V1ServicePort(port=6901, target_port=6901)],
            ),
        ),
    )

    # Reference the wildcard cert only if it exists; Traefik fails to route
    # ingresses that name a missing secret, so fall back to its default cert.
    try:
        core.read_namespaced_secret(TLS_SECRET, NAMESPACE)
        ingress_tls = [k8s.V1IngressTLS(hosts=[f"*.{DOMAIN}"], secret_name=TLS_SECRET)]
    except ApiException:
        ingress_tls = None

    # Ingress routing kasm-<id>.<domain> through the bundled Traefik
    net.create_namespaced_ingress(
        NAMESPACE,
        k8s.V1Ingress(
            metadata=k8s.V1ObjectMeta(name=new_name, labels=labels),
            spec=k8s.V1IngressSpec(
                rules=[
                    k8s.V1IngressRule(
                        host=f"kasm-{new_id}.{DOMAIN}",
                        http=k8s.V1HTTPIngressRuleValue(
                            paths=[
                                k8s.V1HTTPIngressPath(
                                    path="/",
                                    path_type="Prefix",
                                    backend=k8s.V1IngressBackend(
                                        service=k8s.V1IngressServiceBackend(
                                            name=new_name,
                                            port=k8s.V1ServiceBackendPort(number=6901),
                                        )
                                    ),
                                )
                            ]
                        ),
                    )
                ],
                tls=ingress_tls,
            ),
        ),
    )

    if wait_for_instance(new_id):
        rprint(f"[bold green][+] Instance {new_name} created[/bold green]")
        rprint(f"[bold green][+] URL: https://kasm-{new_id}.{DOMAIN}[/bold green]")
        rprint(f"[bold green][+] Password: {new_pass}[/bold green]")
        rprint("[bold green][+] User: kasm_user[/bold green]")
    else:
        rprint(f"[bold red][!] Creation failed; cleaning up {new_name}[/bold red]")
        delete_instance(new_id)
        raise SystemExit(1)


@cli.command(help="Inspect a running Kasm Workspace at ID")
@click.argument("id", type=int)
def inspect(id: int):
    """
    Get details about a running instance
    """
    data = instance_objects(id)
    if data is None:
        rprint(f"[bold red][!] Could not locate instance kasm-{id}[/bold red]")
        return
    rprint(f"[bold cyan]{json.dumps(data, indent=4)}[/bold cyan]")


@cli.command(help="Destroy Kasm Instance at ID")
@click.argument("id", type=int)
def destroy(id: int):
    """
    Removes Ingress, Service, Deployment, and Secret for the given ID
    """
    rprint(f"[bold blue][+] Attempting to destroy kasm-{id}[/bold blue]")
    delete_instance(id)
    rprint(f"[bold green][+] kasm-{id} destroyed[/bold green]")


@cli.command(help="List running Kasm Instances")
def list():
    _, apps, _ = kube()
    deployments = apps.list_namespaced_deployment(NAMESPACE, label_selector=LABEL_SELECTOR)
    now = datetime.now(timezone.utc)
    table = Table(title="Kasm Instances")
    table.add_column("Name")
    table.add_column("Image")
    table.add_column("Age")
    table.add_column("URL")
    for d in sorted(deployments.items, key=lambda d: d.metadata.labels["kasm-id"]):
        id = int(d.metadata.labels["kasm-id"])
        age = now - d.metadata.creation_timestamp
        hours, remainder = divmod(int(age.total_seconds()), 3600)
        minutes, seconds = divmod(remainder, 60)
        table.add_row(
            d.metadata.name,
            d.metadata.labels.get("kasm-image"),
            f"{hours}h{minutes}m{seconds}s",
            instance_url(id),
        )
    rprint(table)


@cli.command(help="Remove all sessions beyond MAX_SESSION_TIME")
def prune():
    """
    Removes all instances older than MAX_SESSION_TIME.
    """
    _, apps, _ = kube()
    deployments = apps.list_namespaced_deployment(NAMESPACE, label_selector=LABEL_SELECTOR)
    now = datetime.now(timezone.utc)
    for d in deployments.items:
        created = d.metadata.creation_timestamp
        if (now - created).total_seconds() >= MAX_SESSION_TIME:
            id = int(d.metadata.labels["kasm-id"])
            rprint(f"[bold yellow][?] Pruning kasm-{id}[/bold yellow]")
            delete_instance(id)


if __name__ == "__main__":
    cli()
