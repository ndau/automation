#!/usr/bin/env python3

"""
Installs nodegroups using the nodegroup helm chart.
"""

import json # for encoding json for helm chart variables
import atexit # to exit gracefully and clean up our temporary docker volume
import pprint # to print config in verbose mode
import os # for environment variables, path, and exits
import subprocess # for running commands
import signal # to handle cleaning after sigint, ctrl+c
import sys # to print to stderr
from base64 import b64encode # for making json safe to send to helm through the command-line
from datetime import datetime, timezone # to datestamp temporary docker volumes
import platform # for dynamically running different builds of addy on different platforms.

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
                "port ({port}) must be within the user or dynamic/private range. (1024-65535)")
        if port < 30000 or port > 32767:
            warn_print(f'Port ({port}) is outside the default kubernetes NodePort range: 30000-32767.')
        return

class Conf:
    """Handles all configuration for this script.
        START_PORT          Port at which to start a sequence of ports.
        SCRIPT_DIR          The absolute path of this script.
        HONEYCOMB_KEY       API key for honeycomb.
        HONEYCOMB_DATASET   Honeycomb data bucket name.
    """

    def __init__(self, args):
        """Initializes with defaults"""

        #
        # Arguments
        #
        self.START_PORT = args.start_port
        global ports
        ports = PortFactory(self.START_PORT)
        self.QUANTITY = args.quantity

        #
        # Environment variables
        #

        self.ELB_SUBDOMAIN = os.environ.get('ELB_SUBDOMAIN')
        if self.ELB_SUBDOMAIN == None:
            abortClean(f'ELB_SUBDOMAIN env var not set.')

        self.RELEASE = os.environ.get('RELEASE')
        if self.RELEASE == None:
            abortClean(f'RELEASE env var not set.')

        self.CHAOS_VERSION = os.environ.get('CHAOS_VERSION')
        if self.CHAOS_VERSION == None:
            try:
                preflight('git', 'grep','awk','cut')  # check environment
            except OSError as e:
                abortClean(f'CHAOS_VERSION env var empty and could not fetch version: {e}')
            self.CHAOS_VERSION = run_command("\
                git ls-remote https://github.com/oneiro-ndev/chaos | \
                grep 'refs/heads/master' | \
                awk '{print $1}' | \
                cut -c1-7").stdout.strip()

        self.NDAU_VERSION = os.environ.get('NDAU_VERSION')
        if self.NDAU_VERSION == None:
            try:
                preflight('git', 'grep','awk','cut')  # check environment
            except OSError as e:
                abortClean(f'NDAU_VERSION env var empty and could not fetch version: {e}')
            self.NDAU_VERSION = run_command("\
                git ls-remote https://github.com/oneiro-ndev/ndau |\
                grep 'refs/heads/master' | \
                awk '{print $1}' | \
                cut -c1-7").stdout.strip()

        self.NOMS_VERSION = os.environ.get('NOMS_VERSION')
        if self.NOMS_VERSION == None:
            try:
                preflight('aws', 'jq','sed','sort','tail')  # check environment
            except OSError as e:
                abortClean(f'NOMS_VERSION env var empty and could not fetch version: {e}')
            self.NOMS_VERSION = run_command("\
                aws ecr list-images --repository-name noms | \
                jq -r '[ .imageIds[] | .imageTag] | .[] ' | \
                sed 's/[^0-9.]//g' | \
                sort --version-sort --field-separator=. | \
                tail -n 1").stdout.strip()

        self.TM_VERSION = os.environ.get('TM_VERSION')
        if self.TM_VERSION == None:
            try:
                preflight('aws', 'jq','sed','sort','tail')  # check environment
            except OSError as e:
                abortClean(f'TM_VERSION env var empty and could not fetch version: {e}')
            self.TM_VERSION = run_command("\
                aws ecr list-images --repository-name tendermint | \
                jq -r '[ .imageIds[] | .imageTag] | .[] ' | \
                sed 's/[^0-9.]//g' | \
                sort --version-sort --field-separator=. | \
                tail -n 1").stdout.strip()

        self.HONEYCOMB_KEY = os.environ.get('HONEYCOMB_KEY')
        self.HONEYCOMB_DATASET = os.environ.get('HONEYCOMB_DATASET')

        #
        # dynamic constants
        #
        self.SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))

        # Path to addy
        exbl = f'addy-{platform.system().lower()}-amd64'
        self.ADDY_CMD = os.path.join(self.SCRIPT_DIR, '..', 'addy', 'dist', exbl)

        # get kubectl context
        context = run_command("kubectl config current-context").stdout.strip()
        self.IS_MINIKUBE = context == "minikube"

        # get IP address of the kubernete's cluster's master node
        self.MASTER_IP = ''
        if (self.IS_MINIKUBE):
            try:
                ret = run_command("minikube ip")
                self.MASTER_IP = ret.stdout.strip()
            except subprocess.CalledProcessError:
                abortClean("Could not get minikube's IP address: ${ret.returncode}")
        else:
            try:
                ret = run_command("kubectl get nodes -o json | \
                    jq -rj '.items[] | select(.metadata.labels[\"kubernetes.io/role\"]==\"master\") | .status.addresses[] | select(.type==\"ExternalIP\") .address'")
                self.MASTER_IP = ret.stdout.strip()
            except subprocess.CalledProcessError:
                abortClean(
                    "Could not get master node's IP address: ${ret.returncode}")

        # add ECR string to image names, or not
        self.ECR = '' if self.IS_MINIKUBE else '578681496768.dkr.ecr.us-east-1.amazonaws.com/'

        if (self.HONEYCOMB_KEY == None or self.HONEYCOMB_DATASET == None):
            steprint('HONEYCOMB_KEY and HONEYCOMB_DATASET must both be set env vars are undefined.\n\
            Logging output will default to stdout/stderr without these vars defined.')

        #
        # Genuine constants
        #

        # Name for a temporary docker volume. New every time.
        self.TMP_VOL = f'tmp-tm-init-{datetime.now(timezone.utc).strftime("%Y-%b-%d-%H-%M-%S")}'

        # used as a prefix for the real command to be run inside the container.
        self.DOCKER_RUN = f'docker run --rm --mount src={self.TMP_VOL},dst=/tendermint '
        pp = pprint.PrettyPrinter(indent=4,stream=sys.stderr)
        vprint('Configuration')
        pp.pprint(self.__dict__)

class Node:
    """Node manages information for a single node."""

    def __init__(self, name):
        """Creates a node."""
        self.name = name
        self.chaos = {
            'port': {
                'p2p': ports.alloc(),
                'rpc': ports.alloc(),
            },
        }
        self.ndau = {
            'port': {
                'p2p': ports.alloc(),
                'rpc': ports.alloc(),
            },
        }

def initNodegroup(nodes):
    """Creates configuration for all nodes using tendermint init."""

    # Initialize tendermint
    for node in nodes:
        steprint(f'\nGenerating config for {node.name}')

        steprint(f'Initializing chaosnode\'s tendermint')
        ret = run_command(f'{c.DOCKER_RUN} \
          -e TMHOME=/tendermint \
          {c.ECR}tendermint:{c.TM_VERSION} \
          init')
        vprint(f'tendermint init: {ret.stdout}')

        steprint(f"Getting priv_validator.json")
        ret = run_command(f'{c.DOCKER_RUN} \
            busybox \
            cat /tendermint/config/priv_validator.json')
        vprint(f'priv_validator: {ret.stdout}')
        node.chaos_priv = json.loads(ret.stdout)

        steprint(f"Getting node_key.json")
        ret = run_command(f'{c.DOCKER_RUN} \
            busybox \
            cat /tendermint/config/node_key.json')
        vprint(f'node_key.json: {ret.stdout}')
        node.chaos_nodeKey = json.loads(ret.stdout)

        steprint('Removing tendermint\'s config directory')
        run_command(f'{c.DOCKER_RUN} \
            busybox \
            rm -rf /tendermint/config')

        steprint(f'Initializing ndaunode\'s tendermint')
        ret = run_command(f'{c.DOCKER_RUN} \
          -e TMHOME=/tendermint \
          {c.ECR}tendermint:{c.TM_VERSION} \
          init')
        vprint(f'tendermint init: {ret.stdout}')

        steprint(f"Getting priv_validator.json")
        ret = run_command(f'{c.DOCKER_RUN} \
            busybox \
            cat /tendermint/config/priv_validator.json')
        vprint(f'priv_validator.json: {ret.stdout}')
        node.ndau_priv = json.loads(ret.stdout)

        steprint(f"Getting node_key.json")
        ret = run_command(f'{c.DOCKER_RUN} \
            busybox \
            cat /tendermint/config/node_key.json')
        vprint(f'node_key.json: {ret.stdout}')
        node.ndau_nodeKey = json.loads(ret.stdout)

        steprint('Removing tendermint\'s config directory')
        run_command(f'{c.DOCKER_RUN} \
            busybox \
            rm -rf /tendermint/config')

    # This uses addy to generate addresses from each node's priv_key
    for node in nodes:
        # chaos
        privKey = node.chaos_nodeKey['priv_key']['value']
        ret = run_command(f'echo "{privKey}" | {c.ADDY_CMD}')
        node.chaos_priv['address'] = ret.stdout
        vprint(f'chaos node_key.priv_key: {privKey}')
        vprint(f'node.chaos_priv: {node.chaos_priv}')

        # ndau
        privKey = node.ndau_nodeKey['priv_key']['value']
        ret = run_command(f'echo "{privKey}" | {c.ADDY_CMD}')
        node.ndau_priv['address'] = ret.stdout
        vprint(f'ndau node_key.priv_key: {privKey}')
        vprint(f'node.ndau_priv: {node.ndau_priv}')

def main():

    import argparse
    parser = argparse.ArgumentParser(description="Installs multiple networked nodegroups to Kubernetes.")
    parser.add_argument('quantity', type=int,
                        help='Quantity of nodegroups to install.')
    parser.add_argument('start_port', type=int, default=30000,
                        help='Starting port for each node\'s Tendermint RPC and P2P ports (e.g. 30000).')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help=('Directory in which to place generated scripts. '
                              f'Default: flase'))

    args = parser.parse_args()

    # allow verbose printing
    global verboseFlag
    verboseFlag = args.verbose

    # get all configuration from the environment
    global c
    c = Conf(args)

    try:
        preflight('docker', 'kubectl')  # check environment tools
    except OSError as e:
        steprint(f'Could not start install: {e}')
        exit(1)

    envSpecificHelmOpts = ''

    if (c.IS_MINIKUBE):
        envSpecificHelmOpts = '\
        --set chaosnode.image.repository="chaos"\
        --set tendermint.image.repository="tendermint"\
        --set noms.image.repository="noms"\
        --set deployUtils.image.repository="deploy-utils"\
        --set deployUtils.image.tag="latest"'
    else:
        envSpecificHelmOpts = '--tls'

    # Create a temporary docker volume
    try:
        makeTempVolume()
    except subprocess.CalledProcessError:
        abortClean("Couldn't create temporary docker volume.")

    nodes = [Node(f'{c.RELEASE}-{i}') for i in range(c.QUANTITY)]

    initNodegroup(nodes)

    steprint('Getting genesis.json...')

    run_command(f'{c.DOCKER_RUN} \
        -e TMHOME=/tendermint \
        {c.ECR}tendermint:{c.TM_VERSION} \
        init')

    ret = run_command(f'{c.DOCKER_RUN} \
        busybox \
        cat /tendermint/config/genesis.json')

    vprint(f'genesis.json: {ret.stdout}')
    chaos_genesis = json.loads(ret.stdout)
    ndau_genesis = json.loads(ret.stdout)

    # add our new nodes
    chaos_genesis['validators'] = list(map(lambda node: {
        'name': node.name,
        'pub_key': node.chaos_priv['pub_key'],
        'power': '10'
    }, nodes))
    ndau_genesis['validators'] = list(map(lambda node: {
        'name': node.name,
        'pub_key': node.ndau_priv['pub_key'],
        'power': '10'
    }, nodes))

    vprint(f'chaos genesis.json: {chaos_genesis}')
    vprint(f'ndau genesis.json: {ndau_genesis}')

    helmChartPath = os.path.join(c.SCRIPT_DIR, '../', 'helm', 'nodegroup')

    # install a node group
    for node in nodes:
        steprint(f'Installing node group: {node.name}')

        # excludes self
        otherNodes = list(filter(lambda peer: peer.name == node.name, nodes))

        # create a string of chaos peers in tendermint's formats
        def chaos_peer(peer):
            return f'{peer.chaos_priv["address"]}@{c.MASTER_IP}:{peer.chaos["port"]["p2p"]}'
        chaosPeers = ','.join(list(map(chaos_peer, otherNodes)))
        chaosPeerIds = ','.join(list(map(lambda peer: peer.chaos_priv['address'], otherNodes)))

        vprint(f'chaos peers: {chaosPeers}')
        vprint(f'chaos peer ids: {chaosPeerIds}')

        chaosLinkOpts = f'\
            --set ndaunode.chaosLink.enabled=true\
            --set ndaunode.chaosLink.address=\"{c.MASTER_IP}:{node.chaos["port"]["rpc"]}\"'

        # create a string of ndau peers in tendermint's formats
        def ndau_peer(peer):
            return f'{peer.ndau_priv["address"]}@{c.MASTER_IP}:{peer.ndau["port"]["p2p"]}'
        ndauPeers = ','.join(list(map(ndau_peer, otherNodes)))
        ndauPeerIds = ','.join(list(map(lambda peer: peer.ndau_priv['address'], otherNodes)))

        vprint(f'ndau peers: {ndauPeers}')
        vprint(f'ndau peer ids: {ndauPeerIds}')

        chaos_args = make_args({
            'chaosnode': {
                'image': {
                    'tag': c.CHAOS_VERSION,
                }
            },
            'chaos': {
                'genesis': jsonB64(chaos_genesis),
                'nodeKey': jsonB64(node.chaos_nodeKey),
                'privValidator': jsonB64(node.chaos_priv),
                'noms': {
                    'image': {
                        'tag': c.NOMS_VERSION,
                    }
                },
                'tendermint': {
                    'moniker': node.name,
                    'persistentPeers': b64(chaosPeers),
                    'privatePeerIds': b64(chaosPeerIds),
                    'image': {
                        'tag': c.TM_VERSION,
                    },
                    'nodePorts': {
                        'enabled': 'true',
                        'p2p': node.chaos['port']['p2p'],
                        'rpc': node.chaos['port']['rpc'],
                    }
                }
            }
        })
        ndau_args = make_args({
            'ndaunode': {'image': {'tag': c.NDAU_VERSION}},
            'ndau': {
                'genesis': jsonB64(ndau_genesis),
                'privValidator': jsonB64(node.ndau_priv),
                'nodeKey': jsonB64(node.ndau_nodeKey),
                'noms': {'image': {'tag': c.NOMS_VERSION}},
                'tendermint': {
                    'image': {'tag': c.TM_VERSION},
                    'moniker': node.name,
                    'persistentPeers': b64(ndauPeers),
                    'privatePeerIds': b64(ndauPeerIds),
                    'nodePorts': {
                        'enabled': 'true',
                        'p2p': node.ndau['port']['p2p'],
                        'rpc': node.ndau['port']['rpc'],
                    }
                }
            },
        })

        helm_command = f'helm install --name {node.name} {helmChartPath} \
            {chaos_args} \
            {ndau_args} \
            --set ndauapi.ingress.enabled=true \
            --set ndauapi.ingress.host="{node.name}.{c.ELB_SUBDOMAIN}" \
            --set honeycomb.key="{c.HONEYCOMB_KEY}" \
            --set honeycomb.dataset="{c.HONEYCOMB_DATASET}" \
            {envSpecificHelmOpts} \
            {chaosLinkOpts}'

        vprint(f'helm command: {helm_command}')
        ret = run_command(helm_command)
        if ret.returncode == 0:
            steprint(f'{node.name} installed successfully')
        else:
            abortClean(f'Installing {node.name} failed.\nstderr: {ret.stderr}\nstdout: {ret.stdout}')

    steprint('All done.')

def preflight(*cmds):
    """Ensures the environment has the necessary command-line tools."""
    missing = []
    for cmd in cmds:
        if not cmd_exists(cmd):
            missing.append(cmd)
    if len(missing) != 0:
        raise OSError(f'Missing the following command-line tools: {",".join(missing)}')

def cmd_exists(x):
    """Return True if the given command exists in PATH."""
    return subprocess.run(
        ['which', x],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0

def run_command(command, isCritical=True):
    """Runs a command in a subprocess."""

    ret = subprocess.run(command,
                            stdout=subprocess.PIPE,
                            universal_newlines=True,
                            stderr=subprocess.STDOUT,
                            shell=True,
    )

    if isCritical and ret.returncode != 0:
        abortClean(f'Command failed with non-zero exit code {ret.returncode}: {command} \nstderr\n{ret.stderr}\nstdout\n{ret.stdout}')

    return ret


def makeTempVolume():
    """Creates a volume for persistence between docker containers."""
    try:
        ret = run_command(f'docker volume create {c.TMP_VOL}')
        steprint(f'Created volume: {c.TMP_VOL}')
        global madeVolume
        madeVolume = True
    except subprocess.CalledProcessError:
        steprint(f'error creating temp volume: {ret.returncode}')


def clean():
    """Attempts to delete the temporary docker volume."""
    global madeVolume
    if madeVolume:
        ret = subprocess.run(["docker", "volume", "rm", c.TMP_VOL],
                                stdout=subprocess.PIPE,
                                universal_newlines=True)
        if ret.returncode == 0:
            steprint(f'Removed volume: {c.TMP_VOL}')
        else:
            steprint(f'Could not delete temporary docker volume: {ret.returncode}\nYou can try: docker volume rm {c.TMP_VOL}')

def abortClean(msg):
    """Runs a cleanup function and exits with a non-zero code."""
    steprint(f'\nAborting install. Error:\n{msg}')
    clean()
    exit(1)


def make_args(opts):
    """
    Converts a dict to a helm-style --set arguments.
    Helm allows you to set one property at a time, which is desirable because it's effectively a merge.
    The drawback is the redundancy and readability. This function allows a dict to represent all of the options.
    """
    args = ''

    def recurse(candidate, accumulator=''):
        nonlocal args
        if isinstance(candidate, dict):
            nonlocal args
            for k, v in candidate.items():
                dotOrNot = "" if accumulator == "" else f'{accumulator}.'
                recurse(v, f'{dotOrNot}{k}')
        elif isinstance(candidate, str):
            args += f'--set {accumulator}="{candidate}" '
        elif isinstance(candidate, int):
            args += f'--set {accumulator}={candidate} '
        else:
            raise ValueError('Leaves must be strings or ints.')

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
    if verboseFlag == True:
        steprint(msg)


def warn_print(msg):
    """Prints a warning message to stderr"""
    steprint(f'\033[93mWARNING\033[0m: {msg}')

def handle_sigint():
    abortClean('Installation cancelled.')

# kick it off
if __name__ == '__main__':
    main()
    clean()

signal.signal(signal.SIGINT, handle_sigint)
