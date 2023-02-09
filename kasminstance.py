class KasmInstance:
    """
    Objects Representing Kasm Workspaces Instances.

    port: int
    container_id: str
    network_id: str
    service_id: str
    vnc_password: str
    """

    def __init__(
        self, \
        port: int = 6901, \
        network_id: str = None, \
        service_id: str = None, \
        vnc_password: str= "password"
    ):
        self.port = port
        self.network_id = network_id
        self.service_id = service_id
        self.vnc_password = vnc_password
        