from random import choice
import docker
import click
import requests
from rich import print as rprint

# Constants
IMAGE_NAME = "tti-kasm-terminal:latest"
CERT_SECRET_NAME = "kasm_cert"
KEY_SECRET_NAME = "kasm_key"
PORT_START = 6901
PORT_END = 7000
PASSWORD_API_URL = "https://passphrase.taggart-tech.com/api/pwlist?n=1&sep=_&digitMin=10&digitMax=99"
PORTS = list(range(PORT_START, PORT_END))

"""
`kasm-manager create`
    1. Choose a random port
    2. Get a random password*
        Store password in docker secrets
    3. Create a new overlay network*
    4. Create a new endpoint spec (port forward mapping)*
    5. Create a new service*
    6. Returns service name/id*

`kasm-manager destroy <PORT>`
    1. Retrieve Docker Secret
    2. Delete Secret
    3. Retrieve Service
    4. Delete Service
    5. Retrieve Network
    6. Delete Network

`kasm-manager list`
    1. Retrieve `kasm_` Services
    2. Print 'em

`kasm-manager inspect <PORT>`
    1.Retrieve `kasm_<PORT>` Service
    2. Print it out
"""
@click.group()
def cli():
    pass

def get_password() -> str:
    r = requests.get(PASSWORD_API_URL)
    try:
        return r.json()[0]
    except:
        raise ConnectionError("Could not retrieve password!")

@cli.command(help="Creates a new Kasm Instance")
def create():
    """
    Launches a new Kasm Instance. Returns the KasmInstance
    """
    client = docker.from_env()

    # Guarantees we only use available ports
    used_ports = [int(i.name.replace("kasm_", "")) for i in client.services.list() if "kasm_" in i.name]
    available_ports = [p for p in PORTS if p not in used_ports]

    # Gets Cert/Key secrets
    try:
        cert_secret = client.secrets.get(CERT_SECRET_NAME)
        cert_secret_ref = docker.types.SecretReference(cert_secret.id, cert_secret.name)
        key_secret = client.secrets.get(KEY_SECRET_NAME)
        key_secret_ref = docker.types.SecretReference(key_secret.id, key_secret.name)
    except:
        rprint(f"[bold red][!] Could not load cert secrets[/bold red]")

    rprint("[bold blue][+] Creating Kasm Instance![/bold blue]")
    new_port = choice(available_ports)
    new_name = f"kasm_{new_port}"
    new_pass = get_password()
    new_secret = client.secrets.create(name=new_name, data=new_pass.encode())
    new_secret_ref = docker.types.SecretReference(new_secret.id, new_secret.name)
    new_net = client.networks.create(f"{new_name}", driver="overlay")
    new_spec = docker.types.EndpointSpec(ports={new_port:6901})
    new_service = client.services.create(
        IMAGE_NAME, \
        name=new_name, \
        env=[f"VNC_PW={new_pass}"], \
        endpoint_spec = new_spec, \
        networks = [new_net.id], \
        secrets = [new_secret_ref, key_secret_ref, cert_secret_ref]
    )
    rprint(f"[bold green][+] Instance {new_name} created[/bold green]")
    rprint(f"[bold green][+] {new_name} Password: {new_pass}[/bold green]")

@cli.command(help="Inspect a running Kasm Korkspace at PORT_ID")
@click.argument("port_id")
def inspect(port_id: int):
    """
    Get details about a running image
    """
    target_name = f"kasm_{port_id}"
    services = {s.name: s for s in client.services.list()}
    client = docker.from_env()
    # Get target service
    try:
        target_service = services[target_name]
    except:
        rprint(f"[bold red][!] Could not locate service {target_name} [/bold red]")
    

@cli.command(help="Destroy Kasm Instance at PORT_ID")
@click.argument("port_id")
def destroy(port_id: int):
    """
    Removes service, network, and secrets for given port id
    """
    client = docker.from_env()

    target_name = f"kasm_{port_id}"

    rprint(f"[bold blue][+] Attempting to destroying {target_name}[/bold blue]")

    # Get all services
    services = {s.name: s for s in client.services.list()}
    networks = {n.name: n for n in client.networks.list()}
    secrets = {s.name:s for s in client.secrets.list()}

    # Get target service
    try:
        target_service = services[target_name]
    except:
        rprint(f"[bold red][!] Could not locate service {target_name} [/bold red]")
        return

    # Get target secret
    try:
        target_secret = secrets[target_name]
    except IndexError:
        rprint(f"[bold red][!] Could not locate secret {target_name} [/bold red]")
        return

    # Get target network
    try:
        target_network = networks[target_name]
    except IndexError:
        rprint(f"[bold red][!] Could not locate network {target_name} [/bold red]")
        return

    rprint(f"[bold red][!] Removing service {target_name} [/bold red]")
    target_service.remove()
    rprint(f"[bold red][!] Removing network {target_name} [/bold red]")
    target_network.remove()
    rprint(f"[bold red][!] Removing secret {target_name} [/bold red]")
    target_secret.remove()

@cli.command()
def list():
    client = docker.from_env()
    services = [s for s in client.services.list() if "kasm_" in s.name]
    for s in services:
        rprint(f"[bold cyan]{s.name}[/bold cyan]")

if __name__ == '__main__':
    cli()