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
import functools # for lru_cache on preflight calls
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
        Command-line arguments:
        START_PORT          Port at which to start a sequence of ports.
        QUANTITY            Number of nodegroups to install.

        Environment variables required
        ELB_SUBDOMAIN       Subdomain for ndauapi. (e.g. api.ndau.tech).
                            Each nodegroup's ndauapi will appear at my-release-0.ndau.tech.
        RELEASE             The helm release "base name". Each nodegroup's name will
                            start with this name and be suffixed with a node number.

        Environment variables that map to image tags in ECR. Optional. Fetched automatically.
        CHAOSNODE_TAG       chaosnode ABCI app.
        NDAUNODE_TAG        ndaunode ABCI app.
        CHAOS_NOMS_TAG      chaosnode's nomsdb.
        CHAOS_TM_TAG        chaosnode's tendermint.
        NDAU_NOMS_TAG       ndaunode's nomsdb.
        NDAU_TM_TAG         ndaunode's tendermint.

        Environment variables that are optional
        HONEYCOMB_KEY       API key for honeycomb.
        HONEYCOMB_DATASET   Honeycomb data bucket name.

        Dynamically generaed constants
        SCRIPT_DIR          The absolute path of this script.
        IS_MINIKUBE         True when kubectl's current context is minikube.
        ECR                 ECR repo's host. For minikube it will use local images.
        ADDY_CMD            Path to the addy utility.
        MASTER_IP           IP of either minikube or the kubernete's cluser master node.

        Genuine constants
        TMP_VOL             Name of a docker volume used for passing things between containers.
        DOCKER_RUN          Command to run a command in a docker image with our temp volume.


    """

    def __init__(self, args):
        """Initializes config with defaults and fetched values."""

        #
        # Arguments
        #
        self.START_PORT = args.start_port
        global ports
        ports = PortFactory(self.START_PORT)
        self.QUANTITY = args.quantity

        if self.QUANTITY < 1:
            abortClean("quantity must be higher than 1")
        elif self.QUANTITY > 16:
            abortClean("quantity should be lower than 16")

        #
        # Environment variables
        #

        self.ELB_SUBDOMAIN = os.environ.get('ELB_SUBDOMAIN')
        if self.ELB_SUBDOMAIN == None:
            abortClean(f'ELB_SUBDOMAIN env var not set.')

        self.RELEASE = os.environ.get('RELEASE')
        if self.RELEASE == None:
            abortClean(f'RELEASE env var not set.')

        self.CHAOSNODE_TAG = os.environ.get('CHAOSNODE_TAG')
        if self.CHAOSNODE_TAG == None:
            try:
                self.CHAOSNODE_TAG = fetch_master_sha('https://github.com/oneiro-ndev/chaos')
            except OSError as e:
                abortClean(f'CHAOSNODE_TAG env var empty and could not fetch version: {e}')


        self.NDAUNODE_TAG = os.environ.get('NDAUNODE_TAG')
        if self.NDAUNODE_TAG == None:
            try:
                self.NDAUNODE_TAG = fetch_master_sha('https://github.com/oneiro-ndev/ndau')
            except OSError as e:
                abortClean(f'NDAUNODE_TAG env var empty and could not fetch version: {e}')

        # chaos noms and tendermint
        self.CHAOS_NOMS_TAG = os.environ.get('CHAOS_NOMS_TAG')
        if self.CHAOS_NOMS_TAG == None:
            try:
                self.CHAOS_NOMS_TAG = highest_version_tag('noms')
            except OSError as e:
                abortClean(f'CHAOS_NOMS_TAG env var empty and could not fetch version: {e}')

        self.CHAOS_TM_TAG = os.environ.get('CHAOS_TM_TAG')
        if self.CHAOS_TM_TAG == None:
            try:
                self.CHAOS_TM_TAG = highest_version_tag('tendermint')
            except OSError as e:
                abortClean(f'CHAOS_TM_TAG env var empty and could not fetch version: {e}')

        # ndau noms and tendermint
        self.NDAU_NOMS_TAG = os.environ.get('NDAU_NOMS_TAG')
        if self.NDAU_NOMS_TAG == None:
            try:
                self.NDAU_NOMS_TAG = highest_version_tag('noms')
            except OSError as e:
                abortClean(f'NDAU_NOMS_TAG env var empty and could not fetch version: {e}')

        self.NDAU_TM_TAG = os.environ.get('NDAU_TM_TAG')
        if self.NDAU_TM_TAG == None:
            try:
                self.NDAU_TM_TAG = highest_version_tag('tendermint')
            except OSError as e:
                abortClean(f'NDAU_TM_TAG env var empty and could not fetch version: {e}')


        self.HONEYCOMB_KEY = os.environ.get('HONEYCOMB_KEY')
        self.HONEYCOMB_DATASET = os.environ.get('HONEYCOMB_DATASET')
        if self.HONEYCOMB_KEY == None or self.HONEYCOMB_DATASET == None:
            self.HONEYCOMB_KEY = ''
            self.HONEYCOMB_DATASET = ''
            warn_print('Logs will be written to stdout/stderr without env vars HONEYCOMB_KEY and HONEYCOMB_DATASET.')

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
        if self.IS_MINIKUBE:
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
                abortClean("Could not get master node's IP address: ${ret.returncode}")

        # add ECR string to image names, or not
        self.ECR = '' if self.IS_MINIKUBE else '578681496768.dkr.ecr.us-east-1.amazonaws.com/'

        #
        # Genuine constants
        #

        # Name for a temporary docker volume. New every time.
        self.TMP_VOL = f'tmp-tm-init-{datetime.now(timezone.utc).strftime("%Y-%b-%d-%H-%M-%S")}'

        # used as a prefix for the real command to be run inside the container.
        self.DOCKER_RUN = f'docker run --rm --mount src={self.TMP_VOL},dst=/tendermint '

        # dump all our config variables in verbose mode
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
          {c.ECR}tendermint:{c.CHAOS_TM_TAG} \
          init')
        vprint(f'tendermint init: {ret.stdout}')

        steprint(f"Getting priv_validator.json")
        ret = run_command(f'{c.DOCKER_RUN} \
            busybox \
            cat /tendermint/config/priv_validator.json')
        # JSG strip all output from above cat until the first brace,
        # when this is run on circle there is extraneous output generated
        # by the first load of busybox image
        priv_val = ret.stdout[ret.stdout.index('{'):]
        vprint(f'priv_validator: {priv_val}')
        node.chaos_priv = json.loads(priv_val)

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
          {c.ECR}tendermint:{c.NDAU_TM_TAG} \
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
        steprint(f'Could not start. Missing tools: {e}')
        exit(1)

    # Create a temporary docker volume
    try:
        makeTempVolume()
    except subprocess.CalledProcessError:
        abortClean("Couldn't create temporary docker volume.")

    nodes = [Node(f'{c.RELEASE}-{i}') for i in range(c.QUANTITY)]

    initNodegroup(nodes)

    steprint('Getting chaos\'s genesis.json')
    run_command(f'{c.DOCKER_RUN} \
        -e TMHOME=/tendermint \
        {c.ECR}tendermint:{c.CHAOS_TM_TAG} \
        init')
    ret = run_command(f'{c.DOCKER_RUN} \
        busybox \
        cat /tendermint/config/genesis.json').stdout

    vprint(f'chaos genesis.json: {ret}')
    chaos_genesis = json.loads(ret)

    steprint('Removing tendermint\'s config directory')
    run_command(f'{c.DOCKER_RUN} \
        busybox \
        rm -rf /tendermint/config')

    steprint('Getting ndau\'s genesis.json')
    run_command(f'{c.DOCKER_RUN} \
        -e TMHOME=/tendermint \
        {c.ECR}tendermint:{c.NDAU_TM_TAG} \
        init')
    ret = run_command(f'{c.DOCKER_RUN} \
        busybox \
        cat /tendermint/config/genesis.json').stdout

    vprint(f'ndau\'s genesis.json: {ret}')
    ndau_genesis = json.loads(ret)

    # add our new nodes to genesis.json's validator list
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
        steprint(f'\nInstalling node group: {node.name}')

        # excludes self
        otherNodes = list(filter(lambda peer: peer.name != node.name, nodes))

        # create a string of chaos peers in tendermint's formats
        def chaos_peer(peer):
            return f'{peer.chaos_priv["address"]}@{c.MASTER_IP}:{peer.chaos["port"]["p2p"]}'
        chaosPeers = ','.join(list(map(chaos_peer, otherNodes)))
        chaosPeerIds = ','.join(list(map(lambda peer: peer.chaos_priv['address'], otherNodes)))

        vprint(f'chaos peers: {chaosPeers}')
        vprint(f'chaos peer ids: {chaosPeerIds}')

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
                    'tag': c.CHAOSNODE_TAG,
                }
            },
            'chaos': {
                'genesis': jsonB64(chaos_genesis),
                'nodeKey': jsonB64(node.chaos_nodeKey),
                'privValidator': jsonB64(node.chaos_priv),
                'noms': {
                    'image': {
                        'tag': c.CHAOS_NOMS_TAG,
                    }
                },
                'tendermint': {
                    'moniker': node.name,
                    'persistentPeers': b64(chaosPeers),
                    'privatePeerIds': b64(chaosPeerIds),
                    'image': {
                        'tag': c.CHAOS_TM_TAG,
                    },
                    'nodePorts': {
                        'enabled': 'true',
                        'p2p': node.chaos['port']['p2p'],
                        'rpc': node.chaos['port']['rpc'],
                    }
                }
            }
        })

        steprint(f'{node.name} chaos P2P port: {node.chaos["port"]["p2p"]}')
        steprint(f'{node.name} chaos RPC port: {node.chaos["port"]["rpc"]}')

        ndau_args = make_args({
            'ndaunode': {'image': {'tag': c.NDAUNODE_TAG}},
            'ndau': {
                'genesis': jsonB64(ndau_genesis),
                'privValidator': jsonB64(node.ndau_priv),
                'nodeKey': jsonB64(node.ndau_nodeKey),
                'noms': {'image': {'tag': c.NDAU_NOMS_TAG}},
                'tendermint': {
                    'image': {'tag': c.NDAU_TM_TAG},
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
        steprint(f'{node.name} ndau P2P port: {node.ndau["port"]["p2p"]}')
        steprint(f'{node.name} ndau RPC port: {node.ndau["port"]["rpc"]}')

        # options that point ndaunode to the chaos node's rpc port
        chaosLinkOpts = f'\
            --set ndaunode.chaosLink.enabled=true\
            --set ndaunode.chaosLink.address=\"{c.MASTER_IP}:{node.chaos["port"]["rpc"]}\"'

        envSpecificHelmOpts = ''

        if c.IS_MINIKUBE:
            envSpecificHelmOpts = '\
            --set chaosnode.image.repository="chaos"\
            --set tendermint.image.repository="tendermint"\
            --set noms.image.repository="noms"\
            --set deployUtils.image.repository="deploy-utils"\
            --set deployUtils.image.tag="latest"'
        else:
            envSpecificHelmOpts = '--tls'

        helm_command = f'helm install --name {node.name} {helmChartPath} \
            {chaos_args} \
            {ndau_args} \
            --set ndauapi.ingress.enabled=true \
            --set-string ndauapi.ingress.host="{node.name}.{c.ELB_SUBDOMAIN}" \
            --set-string ndauapi.image.tag="{c.NDAUNODE_TAG}" \
            --set honeycomb.key="{c.HONEYCOMB_KEY}" \
            --set honeycomb.dataset="{c.HONEYCOMB_DATASET}" \
            {envSpecificHelmOpts} \
            {chaosLinkOpts}'

        vprint(f'helm command: {helm_command}')
        ret = run_command(helm_command, isCritical = False)
        if ret.returncode == 0:
            steprint(f'{node.name} installed successfully')
        else:
            abortClean(f'Installing {node.name} failed.\nstderr: {ret.stderr}\nstdout: {ret.stdout}')

    steprint('All done.')

@functools.lru_cache(4)
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
        abortClean(f'Command failed: {command}\nexit code: {ret.returncode}\nstderr\n{ret.stderr}\nstdout\n{ret.stdout}')
    return ret


def fetch_master_sha(repo):
    """Fetches the 7 character sha from a remote git repo's master branch."""
    preflight('git', 'grep','awk','cut')
    sha = run_command(f"\
        git ls-remote {repo} |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7").stdout.strip()
    vprint(f'{repo} master sha: {sha}')
    return str(sha)

def highest_version_tag(repo):
    """Fetches the latest semver'd version from an AWS ECR repo."""
    preflight('aws', 'jq','sed','sort','tail')  # check environment
    tag = run_command(f"\
        aws ecr list-images --repository-name {repo} | \
        jq -r '[ .imageIds[] | .imageTag] | .[] ' | \
        sed 's/[^0-9.v]//g' | \
        sort --version-sort --field-separator=. | \
        tail -n 1").stdout.strip()
    vprint(f'{repo}\'s highest version tag: {tag}')
    return str(tag)

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
            args += f'--set-string {accumulator}="{candidate}" '
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
