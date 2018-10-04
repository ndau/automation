#!/usr/bin/env python3
"""
gen_node_groups tool.

generate node groups for 
chaosnode/ndaunode/ordernode containers and nodes

usage: gen_node_groups.py #ofnodes starting_port#
"""

import contextlib
import functools
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from base64 import b64encode
from datetime import datetime, timezone
from glob import iglob
from tempfile import NamedTemporaryFile
import platform

"""
import toml
import yaml
"""

P2P_PORT = 26656
RPC_PORT = 26657
PROXY_PORT = 26658
BASE_PORT = 30000

def cmd_exists(x):
    """Return True if the given command exists in PATH."""
    return subprocess.run(
        ['which', x],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


@functools.lru_cache(1)
def project_root():
    """Return the root of this git project."""
    cp = subprocess.run(
        ['git', 'rev-parse', '--show-toplevel'],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        encoding="utf8",
    )
    cp.check_returncode()
    return cp.stdout.strip()


@functools.lru_cache(1)
def empty_hash():
    """Return the chaosnode empty hash."""
    cp = subprocess.run(
        [
            os.path.join(project_root(), 'bin', 'defaults.sh'),
            'docker-compose', 'run', '--rm', '--no-deps',
            'chaosnode', '--echo-empty-hash',
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        encoding="utf8",
    )
    cp.check_returncode()
    return cp.stdout.strip()


@functools.lru_cache(1)
def local_address():
    """Return the local IP address."""
    return socket.gethostbyname(socket.gethostname())


def output_default():
    """Return the directory where the output will be stored."""
    return os.path.join(project_root(), 'bin')


def is_env(item):
    """
    Return `(name, value)` if `item` is an environment variable assignment.

    Otherwise `None`.
    """
    m = re.match(r"^(?P<var>[A-Z_]+)=(?P<quot>\"?)(?P<val>.*)(?P=quot)$", item)
    if m is not None:
        return (m.group('var'), m.group('val'))
    # implicit return None


def sep_env(cmd):
    """
    Given a list of items in a command, split the env from the command.

    `cmd` must be a list from a command line i.e. from shlex.split()

    Returns `(cmd, env)`, where `cmd` is the non-command elements of the
    command, and `env` is a dictionary of the environment set.
    """
    env = {}
    while True:
        maybe_env = is_env(cmd[0])
        if maybe_env is not None:
            env[maybe_env[0]] = maybe_env[1]
            cmd = cmd[1:]
        else:
            break
    return (cmd, env)


class Node:
    """Node manages information for a single node."""

    def __init__(self, num, home, is_validator=True, generate_dc=True):
        """
        Create a node.

        `num` is an identifying number. It must be unique to this node.
        `home` is the collective home of all nodes.
        If `is_validator`, this node is a validator and gets to vote.
        Otherwise, it's a verifier and does not.
        """
        self.num = num
        self.home = home
        self.is_validator = is_validator
        self.name = f'nodegroup{num}'

        # if generate_dc:
        #     with open(self.dcy_path(), 'w', encoding='utf8') as dc:
        #         dc.write(self._generate_docker_compose())

    def chaos_p2p_port(self):
        """Return the exposed p2p port for this service."""
        return BASE_PORT + (4 * self.num)

    def chaos_rpc_port(self):
        """Return the exposed RPC port for this service."""
        return self.chaos_p2p_port() + 1

    def ndau_p2p_port(self):
        """Return the exposed p2p port for this service."""
        return self.chaos_p2p_port() + 2

    def ndau_rpc_port(self):
        """Return the exposed RPC port for this service."""
        return self.chaos_p2p_port() + 3

    @functools.lru_cache(1)
    def node_id(self):
        """Return the node_id tendermint returns for this node."""
        shell = f'docker run --rm --no-deps tendermint show_node_id'
        cr = subprocess.run(
            shell,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            encoding='utf8',
        )
        cr.check_returncode()
        return cr.stdout.strip()

    def p2p_address(self):
        """Return the P2P address of this node."""
        return f'{self.node_id()}@{local_address()}:{self.chaos_p2p_port()}'

    def rpc_address(self):
        """Return the RPC address of this node."""
        return f'http://{local_address()}:{self.chaos_rpc_port()}'

    def path(self, create=False):
        """
        Return the path in which this node stores its homes.

        If `create`, create this directory if it doesn't already exist.
        """
        p = os.path.join(self.home, self.name)
        if create:
            os.makedirs(p, exist_ok=True)
        return p

dockerTmpVol = f'tmp-tm-init-{datetime.now(timezone.utc).strftime("%Y-%b-%d-%H-%M-%S")}' # new volume everytime
madeVolume = False # flag for if volume was created or not. Used for cleanup.

CHAOS_VERSION = os.environ.get('CHAOS_VERSION')
NDAU_VERSION = os.environ.get('NDAU_VERSION')
NOMS_VERSION = os.environ.get('NOMS_VERSION')
TM_VERSION = os.environ.get('TM_VERSION')
HONEYCOMB_KEY = os.environ.get('HONEYCOMB_KEY')
HONEYCOMB_DATASET = os.environ.get('HONEYCOMB_DATASET')
CHAOS_LINK = os.environ.get('CHAOS_LINK')

dockerRun = f'docker run --rm --mount src={dockerTmpVol},dst=/tendermint '

def run_command(command):
    return subprocess.run(command,
        stdout=subprocess.PIPE,
        universal_newlines=True,
        stderr=subprocess.STDOUT,
        shell=True)

def init(nodes, ecr):
    """Initialize all nodes."""
    pub_keys = {}


    # generate `priv_validator.json`
    for node in nodes:
        print(f'initializing {node.name} chaosnode...')
        init_command = f'{dockerRun} \
          -e TMHOME=/tendermint \
          {ecr}tendermint:{TM_VERSION} \
          init'

        ret = run_command(init_command)

        print(f'tm.init = {ret.stdout}')
        
        priv_command = f'{dockerRun} \
            busybox \
            cat /tendermint/config/priv_validator.json'

        ret = run_command(priv_command)

        print(f'node.priv = {ret.stdout}')
        node.chaos_priv = json.loads(ret.stdout)

        print(f"Getting {node.name}'s node key")

        nodekey_command = f'{dockerRun} \
            busybox \
            cat /tendermint/config/node_key.json'

        ret = run_command(nodekey_command)

        print(f'node.nodeKey = {ret.stdout}')
        node.chaos_nodeKey = json.loads(ret.stdout)

        print('Clearing tendermint config')
        rm_command = f'{dockerRun} \
            busybox \
            rm -rf /tendermint/config'

        ret = run_command(rm_command)

        print(f'initializing {node.name} ndaunode...')

        init_command = f'{dockerRun} \
          -e TMHOME=/tendermint \
          {ecr}tendermint:{TM_VERSION} \
          init'

        ret = run_command(init_command)

        print(f'tm.init = {ret.stdout}')
        
        priv_command = f'{dockerRun} \
            busybox \
            cat /tendermint/config/priv_validator.json'

        ret = run_command(priv_command)

        print(f'node.priv = {ret.stdout}')
        node.ndau_priv = json.loads(ret.stdout)

        print(f"Getting {node.name}'s node key")

        nodekey_command = f'{dockerRun} \
            busybox \
            cat /tendermint/config/node_key.json'

        ret = run_command(nodekey_command)

        print(f'node.nodeKey = {ret.stdout}')
        node.ndau_nodeKey = json.loads(ret.stdout)

        print('Clearing tendermint config')
        rm_command = f'{dockerRun} \
            busybox \
            rm -rf /tendermint/config'

        ret = run_command(rm_command)


    print(f'platform = {platform.platform()}, arch = {platform.system()}')

    try:
        exbl = f'addy-{platform.system().lower()}-amd64'
        addyCmd = os.path.join(os.getcwd(), '..', 'addy', 'dist', exbl)
        for node in nodes:
            # process chaos privKey
            privKey = node.chaos_nodeKey['priv_key']['value']
            print(f'chaos privKey = {privKey}')
            ret = run_command(f'echo "{privKey}" | {addyCmd}')
            node.chaos_priv['address'] = ret.stdout
            print(f'node.chaos_priv = {node.chaos_priv}')

            # process ndau privKey
            privKey = node.ndau_nodeKey['priv_key']['value']
            print(f'ndau privKey = {privKey}')
            ret = run_command(f'echo "{privKey}" | {addyCmd}')
            node.ndau_priv['address'] = ret.stdout
            print(f'node.chaos_priv = {node.ndau_priv}')
    except subprocess.CalledProcessError:
        abortClean(f"Couldn't get address from private key: {ret.returncode}")

    return pub_keys

def create_nodes(validators, verifiers, generate_dc=True):
    """Create a list of `Node`s of appropriate types."""
    nodes = []
    for index in range(validators):
        nodes.append(Node(
            index, home,
            is_validator=True, generate_dc=generate_dc,
        ))
    for index in range(verifiers):
        nodes.append(Node(
            index+validators, home,
            is_validator=False, generate_dc=generate_dc,
        ))

    # each node must have a unique number
    assert(len(nodes) == len(set(node.num for node in nodes)))

    return nodes

def emit_rpc_addresses(validators, verifiers):
    """Print all node RPC addresses to stdout."""
    for node in create_nodes(validators, verifiers, generate_dc=False):
        print(node.rpc_address())


def makeTempVolume():
    # create a volume to save genesis.json
    try:
        ret = subprocess.run(["docker", "volume", "create", dockerTmpVol], 
            stdout=subprocess.PIPE,
            universal_newlines=True)
        print(f'Created volume: {dockerTmpVol}')
        madeVolume = True
    except subprocess.CalledProcessError:
        print(f'error creating temp volume: {ret.returncode}')
    
def clean():
  if madeVolume:
    try:
        ret = subprocess.run(["docker", "volume", "rm", dockerTmpVol], 
            stdout=subprocess.PIPE,
            universal_newlines=True)
        print(f'Removed volume: {dockerTmpVol}')
    except subprocess.CalledProcessError:
        print(f'Could not delete temporary docker volume: {ret.returncode}\nYou try: docker volume rm {dockerTmpVol}')

def abortClean(msg):
  print(f'error: {msg}')
  clean()
  exit(1)

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description="Coordinate multiple nodes")
    parser.add_argument('validators', type=int,
                        help='Qty of validators to include')
    parser.add_argument('startPort', type=int, default=0,
                        help='starting port to assign to rpc and p2p ports for the nodes')
    parser.add_argument('-V', '--verifiers', type=int, default=0,
                        help='Qty of verifiers to include')
    parser.add_argument('-H', '--home', default='~/.multinode/',
                        help=('Directory in which to place all node homes. '
                              'Default: ~/.multinode/'))
    parser.add_argument('-o', '--output', default=output_default(),
                        help=('Directory in which to place generated scripts. '
                              f'Default: {output_default()}'))

    args = parser.parse_args()
    home = os.path.expandvars(os.path.expanduser(args.home))
    output = os.path.expandvars(os.path.expanduser(args.output))

    if args.startPort != 0:
        BASE_PORT = args.startPort

    # if args.rpc_address:
    #     emit_rpc_addresses(args.validators, args.verifiers)
    #     sys.exit(0)


    # JSG check to see that HONEYCOMB env vars are set
    if (HONEYCOMB_KEY == None or HONEYCOMB_DATASET == None):
        print('Either HONEYCOMB_KEY or HONEYCOMB_DATASET env vars are undefined.\n\
        Logging output will default to stdout/stderr without these vars defined.')
    

    ret = subprocess.run("kubectl config current-context",
        stdout=subprocess.PIPE,
        universal_newlines=True,
        stderr=subprocess.STDOUT,
        shell=True)
    isMinikube = ''.join(ret.stdout.split()) == "minikube"
    print(f'Detected minikube: : {isMinikube}')

    ecr = '' if isMinikube else '578681496768.dkr.ecr.us-east-1.amazonaws.com/'
    print(f'ecr = {ecr}')

    # get IP address of the master node
    masterIP = ''
    if (isMinikube):
        try:
            ret = run_command("minikube ip")
            masterIP = ''.join(ret.stdout.split())
        except subprocess.CalledProcessError:
            abortClean("Could not get minikube's IP address: ${ret.returncode}")
    else:
        try:
            ret = run_command("kubectl get nodes -o json | \
                jq -rj '.items[] | select(.metadata.labels[\"kubernetes.io/role\"]==\"master\") | .status.addresses[] | select(.type==\"ExternalIP\") .address'")
            print(f'kubectl command: {ret.stdout}')
            masterIP = ret.stdout
        except subprocess.CalledProcessError:
            abortClean("Could not get master node's IP address: ${ret.returncode}")            

    envSpecificHelmOpts = ''

    if (isMinikube):
        envSpecificHelmOpts = '\
        --set chaosnode.image.repository="chaos"\
        --set tendermint.image.repository="tendermint"\
        --set noms.image.repository="noms"\
        --set deployUtils.image.repository="deploy-utils"\
        --set deployUtils.image.tag="latest"'
    else:
        envSpecificHelmOpts = '--tls'

    # start making config

    try:
        makeTempVolume()
    except subprocess.CalledProcessError:
        abortClean("Couldn't create temporary docker volume.")

    nodes = create_nodes(args.validators, args.verifiers)
    pub_keys = init(nodes, ecr)

    print('getting genesis.json...')

    init_command = f'{dockerRun} \
        -e TMHOME=/tendermint \
        {ecr}tendermint:{TM_VERSION} \
        init'

    ret = run_command(init_command)

    shell = f'{dockerRun} \
        busybox \
        cat /tendermint/config/genesis.json'

    ret = run_command(shell)

    print(f'genesis.json = {ret.stdout}')
    chaos_genesis = json.loads(ret.stdout)
    ndau_genesis = json.loads(ret.stdout)

    def chaos_validators(node):
        return {'name': node.name,
            'pub_key': node.chaos_priv['pub_key'],
            'power': '10'}

    def ndau_validators(node):
        return {'name': node.name,
            'pub_key': node.ndau_priv['pub_key'],
            'power': '10'}

    # add our new nodes
    chaos_genesis['validators'] = list(map(chaos_validators, nodes))
    ndau_genesis['validators'] = list(map(ndau_validators, nodes))

    print(f'chaos genesis.json = {chaos_genesis}')
    print(f'ndau genesis.json = {ndau_genesis}')

    nodeGroupDir = os.path.join(os.getcwd(), '../', 'helm', 'nodegroup')
    # chaosDir = os.path.join(os.getcwd(), '../', 'helm', 'chaosnode')

    try:
        # install a chaosnode
        for node in nodes:
            print('Installing {node.name} chaosnode')
            # create a string of peers
            chaosPeerIds = []

            def chaos_create_peers(peer):
                if (peer.name == node.name):
                    return None
                chaosPeerIds.append(peer.chaos_priv['address'])
                return f"{peer.chaos_priv['address']}@{masterIP}:{peer.chaos_p2p_port()}"
            
            chaosPeers = list(map(chaos_create_peers, nodes))

            chaosPeers = ','.join(list(filter(lambda x: x is not None, chaosPeers)))
            chaosPeerIds = ','.join(chaosPeerIds)
            print(f'chaospeers = {chaosPeers}')
            print(f'chaospeerIds = {chaosPeerIds}')

            chaosLinkOpts = f'--set ndaunode.chaosLink.enabled=true\
                --set ndaunode.chaosLink.address="{masterIP}:{node.chaos_rpc_port()}"'

            # create a string of peers
            ndauPeerIds = []

            def ndau_create_peers(peer):
                if (peer.name == node.name):
                    return None
                ndauPeerIds.append(peer.ndau_priv['address'])
                return f"{peer.ndau_priv['address']}@{masterIP}:{peer.ndau_p2p_port()}"
            
            ndauPeers = list(map(ndau_create_peers, nodes))

            ndauPeers = ','.join(list(filter(lambda x: x is not None, ndauPeers)))
            ndauPeerIds = ','.join(ndauPeerIds)
            print(f'ndaupeers = {ndauPeers}')
            print(f'ndaupeerIds = {ndauPeerIds}')

            helm_command = f'helm install --name {node.name} {nodeGroupDir} \
                --set chaos.genesis={b64encode(json.dumps(chaos_genesis).encode()).decode()}\
                --set ndau.genesis={b64encode(json.dumps(ndau_genesis).encode()).decode()}\
                --set chaos.privValidator={b64encode(json.dumps(node.chaos_priv).encode()).decode()}\
                --set ndau.privValidator={b64encode(json.dumps(node.ndau_priv).encode()).decode()}\
                --set chaos.nodeKey={b64encode(json.dumps(node.chaos_nodeKey).encode()).decode()}\
                --set ndau.nodeKey={b64encode(json.dumps(node.ndau_nodeKey).encode()).decode()}\
                --set chaos.tendermint.persistentPeers="{b64encode(chaosPeers.encode()).decode()}" \
                --set ndau.tendermint.persistentPeers="{b64encode(ndauPeers.encode()).decode()}" \
                --set chaos.tendermint.privatePeerIds="{b64encode(chaosPeerIds.encode()).decode()}" \
                --set ndau.tendermint.privatePeerIds="{b64encode(ndauPeerIds.encode()).decode()}" \
                --set chaos.tendermint.nodePorts.enabled=true \
                --set ndau.tendermint.nodePorts.enabled=true \
                --set chaos.tendermint.nodePorts.p2p={node.chaos_p2p_port()} \
                --set ndau.tendermint.nodePorts.p2p={node.ndau_p2p_port()} \
                --set chaos.tendermint.nodePorts.rpc={node.chaos_rpc_port()} \
                --set ndau.tendermint.nodePorts.rpc={node.ndau_rpc_port()} \
                --set chaos.tendermint.moniker={node.name} \
                --set ndau.tendermint.moniker={node.name} \
                --set chaosnode.image.tag={CHAOS_VERSION} \
                --set ndaunode.image.tag={NDAU_VERSION} \
                --set chaos.tendermint.image.tag={TM_VERSION} \
                --set ndau.tendermint.image.tag={TM_VERSION} \
                --set chaos.noms.image.tag={NOMS_VERSION} \
                --set ndau.noms.image.tag={NOMS_VERSION} \
                --set honeycomb.key={HONEYCOMB_KEY} \
                --set honeycomb.dataset={HONEYCOMB_DATASET} \
                {envSpecificHelmOpts} \
                {chaosLinkOpts}'

            # helm_command = f'helm install --name {node.name} {chaosDir} \
            #     --set genesis={b64encode(json.dumps(chaos_genesis).encode()).decode()}\
            #     --set privValidator={b64encode(json.dumps(node.chaos_priv).encode()).decode()}\
            #     --set nodeKey={b64encode(json.dumps(node.chaos_nodeKey).encode()).decode()}\
            #     --set tendermint.persistentPeers="{b64encode(chaosPeers.encode()).decode()}" \
            #     --set tendermint.privatePeerIds="{b64encode(chaosPeerIds.encode()).decode()}" \
            #     --set tendermint.nodePorts.enabled=true \
            #     --set tendermint.nodePorts.p2p={node.chaos_p2p_port()} \
            #     --set tendermint.nodePorts.rpc={node.chaos_rpc_port()} \
            #     --set tendermint.moniker={node.name} \
            #     --set chaosnode.image.tag={CHAOS_VERSION} \
            #     --set tendermint.image.tag={TM_VERSION} \
            #     --set noms.image.tag={NOMS_VERSION} \
            #     --set honeycomb.key={HONEYCOMB_KEY} \
            #     --set honeycomb.dataset={HONEYCOMB_DATASET} \
            #     {envSpecificHelmOpts}'

            print(f'helm shell = {helm_command}')
            ret = run_command(helm_command)
            print(f'helm = {ret.stdout}')

    except subprocess.CalledProcessError:
        abortClean(f'Could not install with helm: {ret.returncode}')


    print('SUCCESS.')
