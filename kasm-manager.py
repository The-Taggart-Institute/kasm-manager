from random import choice
import docker
import requests
from rich import print as rprint
import argparse
from kasminstance import KasmInstance

# Constants
IMAGE_NAME = "kasmweb/terminal:1.12.0-rolling"
PORT_START = 6901
PORT_END = 7000
PASSWORD_API_URL = "https://passphrase.taggart-tech.com/api/pwlist?n=1&sep=_&digitMin=10&digitMax=99"

"""
`kasm-manager create`
    1. Choose a random port
    2. Get a random password*
        Store password in docker secrets
    3. Create a new overlay network
    4. Create a new endpoint spec (port forward mapping)
    5. Create a new service
    6. Returns service name/id

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

def get_password() -> str:
    r = requests.get(PASSWORD_API_URL)
    try:
        return r.json()[0]
    except:
        raise ConnectionError("Could not retrieve password!")
    
def get_port(ports: list) -> int:
    new_port = choice(ports)
    ports.remove(new_port)
    return new_port

# TODO: Get any running instances at launch and remove them from port pool

def launch_instance(client, ports):
    """
    Launches a new Kasm Instance. Returns the KasmInstance

    Parameters
    ==========

    client -> Docker API Client
    """
    new_port = get_port(ports)
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
    return KasmInstance(
        new_port,
        new_net.id,
        new_service.id,
        new_pass 
    )

def main():
    # Initialize parser
    parser = argparse.ArgumentParser(prog="kasm-manager")
    subparsers = parser.add_subparsers(dest="subcommand")
    parser_create = subparsers.add_parser("create", help="Create new Kasm Instance")
    args = parser.parse_args()


    # Initialize Client
    client = docker.from_env()

    # Generate Port Pool
    ports = list(range(PORT_START, PORT_END))
    
    if args.subcommand == "create":
        rprint("[bold blue][+] Creating Kasm Instance![/bold blue]")
        new_instance = launch_instance(client, ports)
        rprint(f"[bold green][+] Instance kasm_{new_instance.port} created[/bold green]")
        rprint(f"[bold green][+] kasm_{new_instance.port} Password: {new_instance.vnc_password}[/bold green]")


if __name__ == "__main__":
    main()