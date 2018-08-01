#!/usr/bin/env node

// This script deploys new chaos nodes in a multiple node network.

const fs = require('fs')
const util = require('util')
const exec = util.promisify(require('child_process').exec)
const readFile = util.promisify(fs.readFile)
const path = require('path');

// async executes an asyncronous function on every element of an array
const asyncForEach = async function (a, cb) {
  for (let i = 0; i < a.length; i++) {
    await cb(a[i], i, a)
  }
}

// str2b64 converts a string into base64
const str2b64 = (s) => Buffer.from(s).toString('base64')

let portCount = 30000 // default starting port

// newPort returns a new port in a series starting on port
const newPort = () => portCount++

// newNode adds a node configuration object to the `nodes` array
const nodes = []
const newNode = (name) => {
  nodes.push({
    name,
    port: {
      p2p: newPort(),
      rpc: newPort()
    }
  })
}

// main will exectute first
async function main() {

  // Usage and argument count validation
  if (process.argv.length < 4 || process.env.VERSION_TAG === undefined) {
    console.log(`
    Please supply a version tag, a port to start and some node names.
    noms and tendermint versions reflect our container versions, not the applications themselves. They are optional and default to "latest".

    Usage
    [NOMS_VERSION=0.0.1] [TM_VERSION=0.0.1] [TOXI=enabled] VERSION_TAG=0.0.1 ./chaos.js 30000 castor pollux
    `)
    process.exit(1)
  }

  const TOXI_ENABLED = process.env.TOXI === "enabled" ? true : false
  const VERSION_TAG = process.env.VERSION_TAG
  const NOMS_VERSION = process.env.NOMS_VERSION || "latest"
  const TM_VERSION = process.env.TM_VERSION || "latest"

  // get the starting port from the arguments
  portCount = parseInt(process.argv[2])

  // get node names from arguments
  const nodeNames = []
  process.argv.forEach((val, i) => {
    if (i > 2) {
      newNode(val)
    }
  })

  // generate validators
  try {
    await asyncForEach(nodes, async (node, i) => {
      const genValidatorCmd = `docker run \
        --rm \
        -e TMHOME=/tendermint \
        578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint:${TM_VERSION} \
        gen_validator`
      let res = await exec(genValidatorCmd, { env: process.env })
      nodes[i].priv = JSON.parse(res.stdout)
    })
  } catch (e) {
    console.log(`Tendermint could not generate validators: ${e}`)
    process.exit(1)
  }

  // generate genesis.json (et al)
  let root = process.env.CIRCLECI == "true" ? "/app" : __dirname
  try {
    // create a volume to save genesis.json
    await exec(`docker volume create genesis`, { env: process.env })
    // run init on our tendermint container
    const initCommand = `docker run \
      --rm \
      -e TMHOME=/tendermint \
      --mount src=genesis,dst=/tendermint \
      578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint:${TM_VERSION} \
      init`
    await exec(initCommand, { env: process.env })
  } catch (e) {
    console.log(`Could not init tendermint: ${e}`)
    // clean up our docker volume
    await exec('docker volume rm genesis', { env: process.env })
    process.exit(1)
  }

  // Get the newly created genesis
  const genesis = {}
  try {
    // output the genesis.json file
    const catGenesisCommand = `docker run \
      --rm \
      --mount src=genesis,dst=/tendermint \
      busybox \
      cat /tendermint/config/genesis.json`
    let newGen = JSON.parse(
      (await exec(catGenesisCommand, { env: process.env }))
        .stdout
    )
    Object.assign(genesis, newGen)
  } catch (e) {
    console.log(`Could not init tendermint: ${e}`)
    process.exit(1)
  } finally {
    // clean up our docker volume
    await exec('docker volume rm genesis', { env: process.env })
  }

  // add our new nodes
  genesis.validators = nodes.map((node) => {
    return {
      name: node.name,
      'pub_key': node.priv.pub_key,
      power: 10
    }
  })

  // Install chaosnodes using helm

  const helmDir = path.join(__dirname, '..', 'helm', 'chaosnode')

  // get IP address of the master node
  let masterIP = ""
  try {
    let res = await exec(`\
      kubectl get nodes -o json | \
      jq -rj '.items[] | select(.metadata.labels["kubernetes.io/role"]=="master") | .status.addresses[] | select(.type=="ExternalIP") .address'`)
    masterIP = res.stdout
  } catch (e) {
    console.log(`Could not get master node's IP address: ${e}`)
    process.exit(1)
  }

  // create a string of peers
  const peers = nodes.map((node) => {
    return `${node.priv.address}@${masterIP}:${node.port.p2p}`
  }).join(',')

  try {

    let res = await exec(`kubectl config current-context`)
    let isMinikube = res.stdout.replace(/\s*/g, '') === 'minikube' ? true : false

    // install a chaosnode
    await asyncForEach(nodes, async (node) => {
      let toxiSettings = ''

      if (TOXI_ENABLED) {
        const rpc = newPort()
        const p2p = newPort()
        toxiSettings = `\
          --set toxiproxy.enabled=true \
          --set toxiproxy.ports.rpc=${rpc} \
          --set toxiproxy.ports.p2p=${p2p} \
        `
        node.port.p2p = p2p
        node.port.rpc = rpc
      }

      let cmd = `helm install --name ${node.name} ${helmDir} \
        --set genesis=${str2b64(JSON.stringify(genesis))}\
        --set privValidator=${str2b64(JSON.stringify(node.priv))}\
        --set persistentPeers="${str2b64(peers)}" \
        --set tendermint.nodePorts.p2p=${node.port.p2p} \
        --set tendermint.nodePorts.rpc=${node.port.rpc} \
        --set tendermint.moniker=${node.name} \
        --set chaosnode.image.tag=${VERSION_TAG} \
        --set tendermint.image.tag=${TM_VERSION} \
        --set noms.image.tag=${NOMS_VERSION} \
        ${toxiSettings} \
        ${isMinikube ? '' : '--tls'}
      `
      console.log(`Installing ${node.name}`)
      await exec(cmd, { env: process.env })
    })

  } catch (e) {
    console.log(`Could not install with helm: ${e}`)
    process.exit(1)
  }

  saveLogs({ nodes, peers, genesis, masterIP })

}

main()

// saveLogs writes a log to a directory
function saveLogs(finalConfig) {
  let timestamp = new Date().toISOString().
    replace(/T/g, '_').
    replace(/\:/g, '-').
    replace(/\..+/, '');

  let logConfigFile = `chaos-config-${timestamp}.json`

  console.log(`Your nodes are configured as follows:\n${JSON.stringify(finalConfig, null, 2)}`)
  console.log(`config log saved to: ${logConfigFile}`)
  fs.writeFile(path.join(__dirname, logConfigFile), JSON.stringify(finalConfig, null, 2), () => { })

}