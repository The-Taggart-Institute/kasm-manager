#!/usr/bin/env python3
from random import choice
from secrets import token_urlsafe
from datetime import datetime, timezone
import base64
import json
import os

import click
import kubernetes
from kubernetes import client as k8s
from kubernetes.client.exceptions import ApiException
from rich import print as rprint
from rich.table import Table

# Constants
# =========
NAMESPACE = "kasm"
IMAGES = {
    "terminal": "taggarttech/tti-kasm-terminal:latest",
    "kali": "taggarttech/tti-kasm-kali:latest"
}
ID_START = 6901   # logical instance IDs, no longer real ports
ID_END = 7000
IDS = list(range(ID_START, ID_END))
PASSWORD_LEN = 20
MAX_SESSION_TIME = 7200
TLS_SECRET = "kasm-wildcard-tls"
LABEL_SELECTOR = "app=kasm"
DOMAIN = os.environ.get("KASM_DOMAIN", "")
# END CONSTANTS
# =============

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


@click.group()
def cli():
    pass


@cli.command(help="Creates a new Kasm Instance")
@click.option("-i", "--image", default="terminal", show_default=True, help="Image type")
def create(image):
    """
    Launches a new Kasm Instance.
    """
    if not DOMAIN:
        rprint("[bold red][!] KASM_DOMAIN is not set. Export it first, e.g. export KASM_DOMAIN=lab.example.com[/bold red]")
        return

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

    rprint(f"[bold green][+] Instance {new_name} created[/bold green]")
    rprint(f"[bold green][+] URL: https://kasm-{new_id}.{DOMAIN}[/bold green]")
    rprint(f"[bold green][+] Password: {new_pass}[/bold green]")
    rprint("[bold green][+] User: kasm_user[/bold green]")


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
