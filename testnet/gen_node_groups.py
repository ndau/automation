#!/usr/bin/env python3

"""
Installs nodegroups using the nodegroup helm chart.
"""

import json  # for encoding json for helm chart variables
import pprint  # to print config in verbose mode
import os  # for environment variables, path, and exits
import subprocess  # for running commands
import signal  # to handle cleaning after sigint, ctrl+c
import sys  # to print to stderr
import functools  # for lru_cache on preflight calls
from datetime import datetime, timezone  # to datestamp temporary docker volumes
import re  # regex for testing validiting when minikube returns an IP.

# for making json safe to send to helm through the command-line
from base64 import b64encode

# for dynamically running different builds of addy on different platforms.
import platform

madeVolume = False  # Flag for if volume was created or not. Used for cleanup.


class PortFactory:
    """Handles creating new sequential ports numbers."""

    def __init__(self, port):
        PortFactory.validate(port)
        self.port = port

    def alloc(self):
        """Returns a new port."""
        self.port += 1
        PortFactory.validate(self.port)
        return self.port

    @staticmethod
    def validate(port):
        if not (port > 1024 and port < 65535):
            abortClean(
                f"port ({port}) must be within the user or dynamic/private range. "
                "(1024-65535)"
            )
        if port < 30000 or port > 32767:
            warn_print(
                f"Port ({port}) is outside the default kubernetes NodePort range: "
                "30000-32767."
            )
        return


class Conf:
    """Handles all configuration for this script.
        Command-line arguments:
        START_PORT          Port at which to start a sequence of ports.
        QUANTITY            Number of nodegroups to install.
        GENESIS_TIME        Time before which no blocks will be issued.
        DRY_RUN             Bool; true if we shouldn't actually deploy

        Environment variables required
        RELEASE             The helm release "base name". Each nodegroup's name will
                            start with this name and be suffixed with a node number.
        ELB_SUBDOMAIN       Subdomain for ndauapi. (e.g. api.ndau.tech).
                            Each nodegroup's ndauapi will appear at RELEASE-0.api.ndau.tech.

        Environment variables that map to image tags in ECR. Optional.
        Fetched automatically.
        CHAOSNODE_TAG       chaosnode ABCI app.
        NDAUNODE_TAG        ndaunode ABCI app.
        CHAOS_NOMS_TAG      chaosnode's nomsdb.
        CHAOS_TM_TAG        chaosnode's tendermint.
        NDAU_NOMS_TAG       ndaunode's nomsdb.
        NDAU_TM_TAG         ndaunode's tendermint.

        Environment variables that are optional
        HONEYCOMB_KEY       API key for honeycomb.
        HONEYCOMB_DATASET   Honeycomb data bucket name.
        SNAPSHOT_CODE       Timestamp of directory to use inside the snapshot bucket.
                            (e.g. 2018-11-16T13-17-16Z)

        Dynamically generaed constants
        SCRIPT_DIR          The absolute path of this script.
        IS_MINIKUBE         True when kubectl's current context is minikube.
        ECR                 ECR repo's host. For minikube it will use local images.
        ADDY_CMD            Path to the addy utility.
        MASTER_IP           IP of either minikube or the kubernete's cluser master node.

        Genuine constants
        TMP_VOL             Name of a docker volume used for passing things
                            between containers.
        DOCKER_RUN          Command to run a command in a docker image with our
                            temp volume.


    """

    def __init__(self, args):
        """Initializes config with defaults and fetched values."""

        #
        # Arguments
        #
        self.QUANTITY = args.quantity
        if self.QUANTITY < 1:
            abortClean("quantity must be at least 1")
        elif self.QUANTITY > 16:
            abortClean("quantity should be lower than 16")

        self.START_PORT = args.start_port
        global ports
        ports = PortFactory(self.START_PORT)

        self.GENESIS_TIME = args.genesis_time
        self.DRY_RUN = args.dry_run

        #
        # Environment variables
        #

        self.ELB_SUBDOMAIN = os.environ.get("ELB_SUBDOMAIN")
        if self.ELB_SUBDOMAIN is None:
            abortClean(f"ELB_SUBDOMAIN env var not set.")

        self.RELEASE = os.environ.get("RELEASE")
        if self.RELEASE is None:
            abortClean(f"RELEASE env var not set.")

        # let commands tag override chaosnode and ndaunode tags
        self.COMMANDS_TAG = os.environ.get("COMMANDS_TAG")
        self.CHAOSNODE_TAG = os.environ.get("CHAOSNODE_TAG")
        self.NDAUNODE_TAG = os.environ.get("NDAUNODE_TAG")

        if self.COMMANDS_TAG is None:
            try:
                self.COMMANDS_TAG = fetch_master_sha(
                    "https://github.com/oneiro-ndev/commands"
                )
                if self.CHAOSNODE_TAG is None:
                    self.CHAOSNODE_TAG = self.COMMANDS_TAG
                if self.NDAUNODE_TAG is None:
                    self.NDAUNODE_TAG = self.COMMANDS_TAG
            except OSError as e:
                abortClean(
                    f"COMMANDS_TAG env var empty and could not fetch version: {e}"
                )
        else:
            if self.CHAOSNODE_TAG is None:
                self.CHAOSNODE_TAG = self.COMMANDS_TAG
            if self.NDAUNODE_TAG is None:
                self.NDAUNODE_TAG = self.COMMANDS_TAG

        # chaos noms and tendermint
        self.CHAOS_NOMS_TAG = os.environ.get("CHAOS_NOMS_TAG")
        if self.CHAOS_NOMS_TAG is None:
            try:
                self.CHAOS_NOMS_TAG = highest_version_tag("noms")
            except OSError as e:
                abortClean(
                    f"CHAOS_NOMS_TAG env var empty and could not fetch version: {e}"
                )

        self.CHAOS_TM_TAG = os.environ.get("CHAOS_TM_TAG")
        if self.CHAOS_TM_TAG is None:
            try:
                self.CHAOS_TM_TAG = highest_version_tag("tendermint")
            except OSError as e:
                abortClean(
                    f"CHAOS_TM_TAG env var empty and could not fetch version: {e}"
                )

        # ndau noms and tendermint
        self.NDAU_NOMS_TAG = os.environ.get("NDAU_NOMS_TAG")
        if self.NDAU_NOMS_TAG is None:
            try:
                self.NDAU_NOMS_TAG = highest_version_tag("noms")
            except OSError as e:
                abortClean(
                    f"NDAU_NOMS_TAG env var empty and could not fetch version: {e}"
                )

        self.NDAU_TM_TAG = os.environ.get("NDAU_TM_TAG")
        if self.NDAU_TM_TAG is None:
            try:
                self.NDAU_TM_TAG = highest_version_tag("tendermint")
            except OSError as e:
                abortClean(
                    f"NDAU_TM_TAG env var empty and could not fetch version: {e}"
                )

        self.SNAPSHOT_CODE = os.environ.get("SNAPSHOT_CODE")
        if self.SNAPSHOT_CODE is None:
            self.SNAPSHOT_CODE = ""

        self.AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
        self.AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")

        self.SNAPSHOT_ON_SHUTDOWN = os.environ.get("SNAPSHOT_ON_SHUTDOWN")
        if self.SNAPSHOT_ON_SHUTDOWN == "true":

            if self.AWS_ACCESS_KEY_ID is None or self.AWS_SECRET_ACCESS_KEY is None:
                abortClean(
                    "If SNAPSHOT_ON_SHUTDOWN is set to true, AWS_ACCESS_KEY_ID and "
                    "AWS_SECRET_ACCESS_KEY need to be set to an account that has "
                    "s3 write permissions on the snapshot bucket."
                )

        self.HONEYCOMB_KEY = os.environ.get("HONEYCOMB_KEY")
        self.HONEYCOMB_DATASET = os.environ.get("HONEYCOMB_DATASET")
        if self.HONEYCOMB_KEY is None or self.HONEYCOMB_DATASET is None:
            self.HONEYCOMB_KEY = ""
            self.HONEYCOMB_DATASET = ""
            warn_print(
                "Logs will be written to stdout/stderr without env vars HONEYCOMB_KEY "
                "and HONEYCOMB_DATASET."
            )

        #
        # dynamic constants
        #
        self.SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))

        # Path to addy
        exbl = f"addy-{platform.system().lower()}-amd64"
        self.ADDY_CMD = os.path.join(self.SCRIPT_DIR, "..", "addy", "dist", exbl)

        # get kubectl context
        context = run_command("kubectl config current-context").stdout.strip()
        self.IS_MINIKUBE = context == "minikube"

        # get IP address of the kubernete's cluster's master node
        self.MASTER_IP = ""
        if self.IS_MINIKUBE:
            try:
                ret = run_command("minikube ip")
                self.MASTER_IP = ret.stdout.strip()
                if re.match("[^0-9.]", self.MASTER_IP) is not None:
                    abortClean(
                        f"IP Address from minikube contains more "
                        f"than numbers and dots: ${self.MASTER_IP}"
                    )
            except subprocess.CalledProcessError:
                abortClean("Could not get minikube's IP address: ${ret.returncode}")
        else:
            try:
                ret = run_command(
                    'kubectl get nodes -o json | \
                        jq -rj \'.items[] | \
                        select(.metadata.labels["kubernetes.io/role"]=="master") | \
                        .status.addresses[] | \
                        select(.type=="ExternalIP") .address\''
                )
                self.MASTER_IP = ret.stdout.strip()
                if re.match("[^0-9.]", self.MASTER_IP) is not None:
                    abortClean(
                        f"IP Address from kubectl contains more "
                        f"than numbers and dots: ${self.MASTER_IP}"
                    )
            except subprocess.CalledProcessError:
                abortClean("Could not get master node's IP address: ${ret.returncode}")

        # add ECR string to image names, or not
        self.ECR = (
            "" if self.IS_MINIKUBE else "578681496768.dkr.ecr.us-east-1.amazonaws.com/"
        )

        #
        # Genuine constants
        #

        # Name for a temporary docker volume. New every time.
        self.TMP_VOL = (
            f'tmp-tm-init-{datetime.now(timezone.utc).strftime("%Y-%b-%d-%H-%M-%S")}'
        )

        # used as a prefix for the real command to be run inside the container.
        self.DOCKER_RUN = f"docker run --rm --mount src={self.TMP_VOL},dst=/tendermint "

        # dump all our config variables in verbose mode
        vpprint("Configuration", self.__dict__)


class Node:
    """Node manages information for a single node."""

    def __init__(self, name):
        """Creates a node."""
        self.name = name
        self.chaos = {"port": {"p2p": ports.alloc(), "rpc": ports.alloc()}}
        self.ndau = {"port": {"p2p": ports.alloc(), "rpc": ports.alloc()}}


def initNodegroup(nodes):
    """Creates configuration for all nodes using tendermint init."""

    # Initialize tendermint
    for node in nodes:
        steprint(f"\nGenerating config for {node.name}")

        steprint(f"Initializing chaosnode's tendermint")
        ret = run_command(
            f"{c.DOCKER_RUN} -e TMHOME=/tendermint "
            f"{c.ECR}tendermint:{c.CHAOS_TM_TAG} init"
        )
        vprint(f"tendermint init: {ret.stdout}")

        steprint(f"Getting priv_validator_key.json")
        ret = run_command(
            f"{c.DOCKER_RUN} busybox cat /tendermint/config/priv_validator_key.json"
        )
        # JSG strip all output from above cat until the first brace,
        # when this is run on circle there is extraneous output generated
        # by the first load of busybox image
        priv_val = ret.stdout[ret.stdout.index("{") :]
        vprint(f"priv_validator: {priv_val}")
        node.chaos_priv = json.loads(priv_val)

        steprint(f"Getting node_key.json")
        ret = run_command(
            f"{c.DOCKER_RUN} busybox cat /tendermint/config/node_key.json"
        )
        vprint(f"node_key.json: {ret.stdout}")
        node.chaos_nodeKey = json.loads(ret.stdout)

        steprint("Removing tendermint's config directory")
        run_command(f"{c.DOCKER_RUN} busybox rm -rf /tendermint/config")

        steprint(f"Initializing ndaunode's tendermint")
        ret = run_command(
            f"{c.DOCKER_RUN} -e TMHOME=/tendermint "
            f"{c.ECR}tendermint:{c.NDAU_TM_TAG} init"
        )
        vprint(f"tendermint init: {ret.stdout}")

        steprint(f"Getting priv_validator_key.json")
        ret = run_command(
            f"{c.DOCKER_RUN} busybox cat /tendermint/config/priv_validator_key.json"
        )
        vprint(f"priv_validator_key.json: {ret.stdout}")
        node.ndau_priv = json.loads(ret.stdout)

        steprint(f"Getting node_key.json")
        ret = run_command(
            f"{c.DOCKER_RUN} busybox cat /tendermint/config/node_key.json"
        )
        vprint(f"node_key.json: {ret.stdout}")
        node.ndau_nodeKey = json.loads(ret.stdout)

        steprint("Removing tendermint's config directory")
        run_command(f"{c.DOCKER_RUN} busybox rm -rf /tendermint/config")

    # This uses addy to generate addresses from each node's priv_key
    for node in nodes:
        # chaos
        privKey = node.chaos_nodeKey["priv_key"]["value"]
        ret = run_command(f'echo "{privKey}" | {c.ADDY_CMD}')
        node.chaos_priv["address"] = ret.stdout
        vprint(f"chaos node_key.priv_key: {privKey}")
        vprint(f"node.chaos_priv: {node.chaos_priv}")

        # ndau
        privKey = node.ndau_nodeKey["priv_key"]["value"]
        ret = run_command(f'echo "{privKey}" | {c.ADDY_CMD}')
        node.ndau_priv["address"] = ret.stdout
        vprint(f"ndau node_key.priv_key: {privKey}")
        vprint(f"node.ndau_priv: {node.ndau_priv}")


def main():

    import argparse

    parser = argparse.ArgumentParser(
        description="Installs multiple networked nodegroups to Kubernetes."
    )
    parser.add_argument("quantity", type=int, help="Quantity of nodegroups to install.")
    parser.add_argument(
        "start_port",
        type=int,
        default=30000,
        help="Starting port for each node's Tendermint RPC and P2P ports (e.g. 30000).",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="When set emit more."
    )
    parser.add_argument(
        "--genesis-time",
        type=iso8601,
        default=datetime.now(),
        help=(
            "ISO-8601 datetime for genesis. "
            "Tendermint will wait for this datetime before processing blocks."
        ),
    )
    parser.add_argument(
        "-D",
        "--dry-run",
        action="store_true",
        help="If set, do not actually deploy anything",
    )

    args = parser.parse_args()

    # allow verbose printing
    global verboseFlag
    verboseFlag = args.verbose

    # get all configuration from the environment
    global c
    c = Conf(args)

    try:
        preflight("docker", "kubectl")  # check environment tools
    except OSError as e:
        steprint(f"Could not start. Missing tools: {e}")
        exit(1)

    # Create a temporary docker volume
    try:
        makeTempVolume()
    except subprocess.CalledProcessError:
        abortClean("Couldn't create temporary docker volume.")

    nodes = [Node(f"{c.RELEASE}-{i}") for i in range(c.QUANTITY)]
    initNodegroup(nodes)

    steprint("Getting chaos's genesis.json")
    run_command(
        f"{c.DOCKER_RUN} -e TMHOME=/tendermint "
        f"{c.ECR}tendermint:{c.CHAOS_TM_TAG} init"
    )
    ret = run_command(
        f"{c.DOCKER_RUN} busybox cat /tendermint/config/genesis.json"
    ).stdout

    vprint(f"chaos genesis.json: {ret}")
    chaos_genesis = conf_genesis_json(json.loads(ret), "chaos", nodes)

    steprint("Removing tendermint's config directory")
    run_command(f"{c.DOCKER_RUN} busybox rm -rf /tendermint/config")

    steprint("Getting ndau's genesis.json")
    run_command(
        f"{c.DOCKER_RUN} -e TMHOME=/tendermint {c.ECR}tendermint:{c.NDAU_TM_TAG} init"
    )
    ret = run_command(
        f"{c.DOCKER_RUN} busybox cat /tendermint/config/genesis.json"
    ).stdout

    vprint(f"ndau's genesis.json: {ret}")
    ndau_genesis = conf_genesis_json(json.loads(ret), "ndau", nodes)

    vprint(f"chaos genesis.json: {chaos_genesis}")
    vprint(f"ndau genesis.json: {ndau_genesis}")

    network_dir = os.path.join(c.SCRIPT_DIR, f"network-{c.RELEASE}")

    if os.path.exists(network_dir):
        for i in range(0, 32):
            candidate_dir = f"{network_dir}-{i}"
            if not os.path.exists(candidate_dir):
                network_dir = candidate_dir
                break

    try:
        os.mkdir(network_dir)
    except OSError:
        abortClean(f"Couldn't create directory: {network_dir}")
    else:
        vprint(f"Created directory: {network_dir}")

    up_cmd = """#!/bin/bash\n\nif [ -z "$HELM_CHART_PATH" ]; then
        >&2 echo HELM_CHART_PATH required; exit 1; fi\n\n"""
    down_cmd = "#!/bin/bash\n\n"

    # install a node group
    for idx, node in enumerate(nodes):
        steprint(f"\nInstalling node group: {node.name}")

        # excludes self
        otherNodes = list(filter(lambda peer: peer.name != node.name, nodes))

        # create a string of chaos peers in tendermint's formats
        def chaos_peer(peer):
            return (
                f'{peer.chaos_priv["address"]}@{c.MASTER_IP}:'
                f'{peer.chaos["port"]["p2p"]}'
            )

        chaosPeers = ",".join(list(map(chaos_peer, otherNodes)))
        chaosPeerIds = ",".join(
            list(map(lambda peer: peer.chaos_priv["address"], otherNodes))
        )

        vprint(f"chaos peers: {chaosPeers}")
        vprint(f"chaos peer ids: {chaosPeerIds}")

        # create a string of ndau peers in tendermint's formats
        def ndau_peer(peer):
            return (
                f'{peer.ndau_priv["address"]}@{c.MASTER_IP}'
                f':{peer.ndau["port"]["p2p"]}'
            )

        ndauPeers = ",".join(list(map(ndau_peer, otherNodes)))
        ndauPeerIds = ",".join(
            list(map(lambda peer: peer.ndau_priv["address"], otherNodes))
        )

        vprint(f"ndau peers: {ndauPeers}")
        vprint(f"ndau peer ids: {ndauPeerIds}")

        chaos_args = make_args(
            {
                "chaosnode": {"image": {"tag": "$CHAOSNODE_TAG"}},
                "chaos": {
                    "genesis": jsonB64(chaos_genesis),
                    "nodeKey": jsonB64(node.chaos_nodeKey),
                    "privValidator": jsonB64(node.chaos_priv),
                    "noms": {
                        "snapshotCode": c.SNAPSHOT_CODE,
                        "image": {"tag": "$CHAOS_NOMS_TAG"},
                    },
                    "tendermint": {
                        "moniker": node.name,
                        "persistentPeers": b64(chaosPeers),
                        "privatePeerIds": b64(chaosPeerIds),
                        "image": {"tag": "$CHAOS_TM_TAG"},
                        "nodePorts": {
                            "enabled": "true",
                            "p2p": node.chaos["port"]["p2p"],
                            "rpc": node.chaos["port"]["rpc"],
                        },
                    },
                },
            }
        )

        steprint(f'{node.name} chaos P2P port: {node.chaos["port"]["p2p"]}')
        steprint(f'{node.name} chaos RPC port: {node.chaos["port"]["rpc"]}')

        ndau_args = make_args(
            {
                "ndaunode": {"image": {"tag": "$NDAUNODE_TAG"}},
                "ndau": {
                    "genesis": jsonB64(ndau_genesis),
                    "privValidator": jsonB64(node.ndau_priv),
                    "nodeKey": jsonB64(node.ndau_nodeKey),
                    "noms": {
                        "snapshotCode": c.SNAPSHOT_CODE,
                        "image": {"tag": "$NDAU_NOMS_TAG"},
                    },
                    "tendermint": {
                        "image": {"tag": "$NDAU_TM_TAG"},
                        "moniker": node.name,
                        "persistentPeers": b64(ndauPeers),
                        "privatePeerIds": b64(ndauPeerIds),
                        "nodePorts": {
                            "enabled": "true",
                            "p2p": node.ndau["port"]["p2p"],
                            "rpc": node.ndau["port"]["rpc"],
                        },
                    },
                },
            }
        )
        steprint(f'{node.name} ndau P2P port: {node.ndau["port"]["p2p"]}')
        steprint(f'{node.name} ndau RPC port: {node.ndau["port"]["rpc"]}')

        envSpecificHelmOpts = ""

        if c.IS_MINIKUBE:
            envSpecificHelmOpts = "--set minikube=true "
        else:
            envSpecificHelmOpts = "--tls"

        # This big line-continuation is ugly but the alternative of
        # concatenated fstrings is worse.
        helm_command = f'helm install --name {node.name} $HELM_CHART_PATH \
            {chaos_args} \
            {ndau_args} \
            --set snapshotOnShutdown={c.SNAPSHOT_ON_SHUTDOWN} \
            --set aws.accessKeyID="$AWS_ACCESS_KEY_ID" \
            --set aws.secretAccessKey="$AWS_SECRET_ACCESS_KEY" \
            --set ndau.deployUtils.image.tag="0.0.4" \
            --set chaos.deployUtils.image.tag="0.0.4" \
            --set ndauapi.ingress.enabled=true \
            --set-string ndauapi.ingress.host="{node.name}.{c.ELB_SUBDOMAIN}" \
            --set-string ndauapi.image.tag="$NDAUNODE_TAG" \
            --set honeycomb.key="$HONEYCOMB_KEY" \
            --set honeycomb.dataset="$HONEYCOMB_DATASET" \
            {envSpecificHelmOpts}'

        vprint(f"helm command: {helm_command}")

        f_name = f"node-{idx}.sh"
        down_cmd += f"helm del {node.name} --purge --tls\n"
        up_cmd += f"./{f_name}\n"
        f_path = os.path.join(network_dir, f_name)
        f = open(f_path, "w")
        f.write(f"#!/bin/bash\n{helm_command}")
        f.close()
        os.chmod(f_path, 0o777)

    # save the up.sh script
    up_path = os.path.join(network_dir, "up.sh")
    f = open(up_path, "w")
    f.write(up_cmd)
    f.close()
    os.chmod(up_path, 0o777)

    # save the down.sh script
    down_path = os.path.join(network_dir, "down.sh")
    f = open(down_path, "w")
    f.write(down_cmd)
    f.close()
    os.chmod(down_path, 0o777)

    # zip it up
    try:
        ret = run_command(f"cd {network_dir}; tar czf {c.RELEASE}.tgz * ")
        steprint(f"Created tar ball: {network_dir}/{c.RELEASE}.tgz")
    except subprocess.CalledProcessError:
        steprint(f"Error creating tar ball: {ret.returncode}")

    steprint("All done.")


def preflight(*cmds):
    """Ensures the environment has the necessary command-line tools."""
    missing = []
    for cmd in cmds:
        if not cmd_exists(cmd):
            missing.append(cmd)
    if len(missing) != 0:
        raise OSError(f'Missing the following command-line tools: {",".join(missing)}')


@functools.lru_cache()
def cmd_exists(x):
    """Return True if the given command exists in PATH."""
    return (
        subprocess.run(
            ["which", x], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode
        == 0
    )


def run_command(command, isCritical=True):
    """Runs a command in a subprocess."""
    ret = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        universal_newlines=True,
        stderr=subprocess.STDOUT,
        shell=True,
    )
    if isCritical and ret.returncode != 0:
        abortClean(
            f"Command failed: {command}\n"
            f"exit code: {ret.returncode}\n"
            f"stderr\n{ret.stderr}\n"
            f"stdout\n{ret.stdout}"
        )
    return ret


def fetch_master_sha(repo):
    """Fetches the 7 character sha from a remote git repo's master branch."""
    preflight("git", "grep", "awk", "cut")
    sha = run_command(
        f"\
        git ls-remote {repo} |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7"
    ).stdout.strip()
    vprint(f"{repo} master sha: {sha}")
    return str(sha)


def highest_version_tag(repo):
    """Fetches the latest semver'd version from an AWS ECR repo."""
    preflight("aws", "jq", "sed", "sort", "tail")  # check environment
    tag = run_command(
        f"\
        aws ecr list-images --repository-name {repo} | \
        jq -r '[ .imageIds[] | .imageTag] | .[] ' | \
        sed 's/[^0-9.v]//g' | \
        sort --version-sort --field-separator=. | \
        tail -n 1"
    ).stdout.strip()
    vprint(f"{repo}'s highest version tag: {tag}")
    return str(tag)


def makeTempVolume():
    """Creates a volume for persistence between docker containers."""
    try:
        ret = run_command(f"docker volume create {c.TMP_VOL}")
        steprint(f"Created volume: {c.TMP_VOL}")
        global madeVolume
        madeVolume = True
    except subprocess.CalledProcessError:
        steprint(f"error creating temp volume: {ret.returncode}")


def conf_genesis_json(gj, chain, nodes):
    "Config genesis.json"
    gj["genesis_time"] = c.GENESIS_TIME.isoformat()
    gj["chain_id"] = chain
    gj["validators"] = [
        {"name": node.name, "pub_key": node.chaos_priv["pub_key"], "power": "10"}
        for node in nodes
    ]

    return gj


def clean():
    """Attempts to delete the temporary docker volume."""
    global madeVolume
    if madeVolume:
        ret = subprocess.run(
            ["docker", "volume", "rm", c.TMP_VOL],
            stdout=subprocess.PIPE,
            universal_newlines=True,
        )
        if ret.returncode == 0:
            steprint(f"Removed volume: {c.TMP_VOL}")
        else:
            steprint(
                f"Could not delete temporary docker volume: {ret.returncode}\n"
                f"You can try: docker volume rm {c.TMP_VOL}"
            )


def abortClean(msg):
    """Runs a cleanup function and exits with a non-zero code."""
    steprint(f"\nAborting install. Error:\n{msg}")
    clean()
    exit(1)


def make_args(opts):
    """
    Converts a dict to a helm-style --set and --set-string arguments.
    Helm allows you to set one property at a time, which is desirable because
    it's effectively a merge.
    The drawback is the redundancy and readability.
    This function allows a dict to represent all of the options.
    """
    args = ""

    def recurse(candidate, accumulator=""):
        nonlocal args
        if isinstance(candidate, dict):
            nonlocal args
            for k, v in candidate.items():
                dotOrNot = "" if accumulator == "" else f"{accumulator}."
                recurse(v, f"{dotOrNot}{k}")
        elif isinstance(candidate, str):
            args += f'--set-string {accumulator}="{candidate}" '
        elif isinstance(candidate, int):
            args += f"--set {accumulator}={candidate} "
        else:
            raise ValueError("Leaves must be strings or ints.")

    recurse(opts)
    return args


def jsonB64(val):
    """Returns base-64 encoded JSON."""
    return b64encode(json.dumps(val).encode()).decode()


def b64(val):
    """Returns a string encoded in base-64."""
    return b64encode(val.encode()).decode()


def steprint(*args, **kwargs):
    """Prints to stderr."""
    print(*args, file=sys.stderr, **kwargs)


def vprint(msg):
    """Prints when the verboseFlag is set to true"""
    if verboseFlag:
        steprint(msg)


def vpprint(hdr, obj):
    """Pretty-prints when the verboseFlag is set to true"""
    if verboseFlag:
        pp = pprint.PrettyPrinter(indent=4, stream=sys.stderr)
        steprint("Configuration")
        pp.pprint(obj)


def warn_print(msg):
    """Prints a warning message to stderr"""
    steprint(f"\033[93mWARNING\033[0m: {msg}")


def handle_sigint():
    abortClean("Installation cancelled.")


def iso8601(s):
    # this is a very strict parser, but it's useful in that it requires us to
    # submit zulu time, which is the only time we're certain the reading code
    # knows how to handle
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)


# kick it off
if __name__ == "__main__":
    main()
    clean()

signal.signal(signal.SIGINT, handle_sigint)
