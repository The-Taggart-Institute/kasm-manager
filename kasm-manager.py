from random import choice
import docker
import click
import requests
from rich import print as rprint
import argparse

# Constants
IMAGE_NAME = "kasmweb/terminal:1.12.0-rolling"
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

# TODO: Get any running instances at launch and remove them from port pool

@cli.command(help="Creates a new Kasm Instance")
def create():
    """
    Launches a new Kasm Instance. Returns the KasmInstance
    """
    client = docker.from_env()

    # Guarantees we only use available ports
    used_ports = [int(i.name.replace("kasm_", "")) for i in client.services.list() if "kasm_" in i.name]
    available_ports = [p for p in PORTS if p not in used_ports]

    rprint("[bold blue][+] Creating Kasm Instance![/bold blue]")
    new_port = choice(available_ports)
    new_pass = get_password()
    new_net = client.networks.create(f"kasm_{new_port}", driver="overlay")
    new_spec = docker.types.EndpointSpec(ports={new_port:6901})
    new_service = client.services.create(
        IMAGE_NAME, \
        name=f"kasm_{new_port}", \
        env=[f"VNC_PW={new_pass}"], \
        endpoint_spec = new_spec, \
        networks = [new_net.id]
    )
    rprint(f"[bold green][+] Instance kasm_{new_port} created[/bold green]")
    rprint(f"[bold green][+] kasm_{new_port} Password: {new_pass}[/bold green]")
    
@cli.command(help="Destroy Kasm Instance at PORT_ID")
@click.argument("port_id")
def destroy(port_id: int):
    """
    Removes service, network, and secrets for given port id
    """
    client = docker.from_env()

    target_name = f"kasm_{port_id}"

    services = client.services.list()
    networks = client.networks.list()

    target_service = list(filter(lambda s: s.name == target_name, services))[0]
    target_network = list(filter(lambda s: s.name == target_name, networks))[0]

    rprint(f"[bold red][!] Removing service {target_name} [/bold red]")
    target_service.remove()
    rprint(f"[bold red][!] Removing network {target_name} [/bold red]")
    target_network.remove()

if __name__ == '__main__':
    cli()