#!/usr/bin/env node

// This script deploys new chaos nodes in a multiple node network.

const os = require('os')
const fs = require('fs')
const util = require('util')
const exec = util.promisify(require('child_process').exec)
const writeFile = util.promisify(fs.writeFile)
const path = require('path')

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

const dockerTmpVol = `tmp-tm-init-${(new Date()).getTime()}` // new volume everytime
global.madeVolume = false // flag for if volume was created or not. Used for cleanup.
const makeTempVolume = async () => {
  try {
    // create a volume to save genesis.json
    await exec(`docker volume create ${dockerTmpVol}`, { env: process.env })
    console.error(`Created volume: ${dockerTmpVol}`)
    global.madeVolume = true
  } catch (e) {
    throw e
  }
}

const clean = async () => {
  if (global.madeVolume) {
    try {
      await exec(`docker volume rm ${dockerTmpVol}`, { env: process.env })
      console.error(`Removed volume: ${dockerTmpVol}`)
    } catch (e) {
      console.error('\x1b[31m%s\x1b[0m', `Could not delete temporary docker volume:\x1b[0m ${e}\n\nYou try: docker volume rm ${dockerTmpVol}`)
    }
  }
}

const abortClean = (msg) => {
  console.error('\x1b[31m%s\x1b[0m', msg, '\x1b[0m')
  clean()
  process.exit(1)
}

// main will exectute first
async function main () {
  // Usage and argument count validation
  if (process.argv.length < 4 || process.env.VERSION_TAG === undefined) {
    console.error(`
    Please supply a version tag, a port to start and some node names.
    noms and tendermint versions reflect our container versions, not the applications themselves. They are optional and default to "latest".

    Usage
    [NOMS_VERSION=0.0.1] [TM_VERSION=0.0.1] [TOXI=enabled] VERSION_TAG=0.0.1 ./chaos.js 30000 castor pollux
    `)
    process.exit(1)
  }

  const TOXI_ENABLED = process.env.TOXI === "enabled" ? true : false
  const VERSION_TAG = process.env.VERSION_TAG
  const NOMS_VERSION = process.env.NOMS_VERSION || 'latest'
  const TM_VERSION = process.env.TM_VERSION || 'latest'

  // get the starting port from the arguments
  portCount = parseInt(process.argv[2])

  // get node names from arguments
  process.argv.forEach((val, i) => {
    if (i > 2) {
      newNode(val)
    }
  })

  /*
   * Environment related
   */

  // check for minikube
  let isMinikube = false
  try {
    let res = await exec(`kubectl config current-context`)
    isMinikube = res.stdout.replace(/\s*/g, '') === 'minikube'
  } catch (e) {
    abortClean(`Could not get current context: ${e}`)
  }
  console.error(`Detected minikube: ${isMinikube}`)

  const ecr = isMinikube ? '' : '578681496768.dkr.ecr.us-east-1.amazonaws.com/'

  // get IP address of the master node
  let masterIP = ''
  if (isMinikube) {
    try {
      masterIP = (await exec(`minikube ip`)).stdout.replace(/\s+/, '')
    } catch (e) {
      abortClean(`Could not get minikube's IP address: ${e}`)
    }
  } else {
    try {
      masterIP = (await exec(`\
        kubectl get nodes -o json | \
        jq -rj '.items[] | select(.metadata.labels["kubernetes.io/role"]=="master") | .status.addresses[] | select(.type=="ExternalIP") .address'`)
      ).stdout
    } catch (e) {
      abortClean(`Could not get master node's IP address: ${e}`)
    }
  }

  let envSpecificHelmOpts = ''
  if (isMinikube) {
    envSpecificHelmOpts = `\
      --set chaosnode.image.repository="chaos"\
      --set tendermint.image.repository="tendermint"\
      --set noms.image.repository="noms"\
      --set deployUtils.image.repository="deploy-utils"\
      --set deployUtils.image.tag="latest"`
  } else {
    envSpecificHelmOpts = `--tls`
  }

  /*
   * start making config
   */

  try {
    await makeTempVolume()
  } catch (e) {
    abortClean(`Couldn't create temporary docker volume. ${e}`)
  }

  // command to run an unspecified docker container with a shared volume
  const dockerRun = `docker run --rm --mount src=${dockerTmpVol},dst=/tendermint `

  // generate validators and node keys
  try {
    await asyncForEach(nodes, async (node, i) => {
      // initialize tendermint first
      console.error(`Initializing ${node.name}'s tendermint configs`)
      return exec(`${dockerRun} \
          -e TMHOME=/tendermint \
          ${ecr}tendermint:${TM_VERSION} \
          init`, { env: process.env })
        .then((res) => {
          // cat priv_validator
          console.error(`Getting ${node.name}'s priv validator`)
          return exec(`${dockerRun} \
            busybox \
            cat /tendermint/config/priv_validator.json`, { env: process.env })
        })
        .then((res) => {
          // remember priv validator
          nodes[i].priv = JSON.parse(res.stdout)
        })
        .then((res) => {
          // cat node_key
          console.error(`Getting ${node.name}'s node key`)
          return exec(`${dockerRun} \
            busybox \
            cat /tendermint/config/node_key.json`, { env: process.env })
        })
        .then((res) => {
          // remember node key
          nodes[i].nodeKey = JSON.parse(res.stdout)
        })
        .then((res) => {
          // reset tendermint config
          console.error(`Clearing tendermint config`)
          return exec(`${dockerRun} \
            busybox \
            rm -rf /tendermint/config`, { env: process.env })
        })
        .catch((e) => { abortClean(`Failed to get config files: ${e}`) })
    })
  } catch (e) {
    abortClean(`Tendermint could not init: ${e}`)
  }

  // Update priv key addresses with the real addresses
  try {
    const exbl = `addy-${os.platform()}-${os.arch().replace('x64', 'amd64')}`
    const addyCmd = path.join(__dirname, '..', 'addy', 'dist', exbl)
    await asyncForEach(nodes, async (node, i) => {
      const privKey = node.nodeKey['priv_key'].value
      const res = await exec(`echo "${privKey}" | ${addyCmd}`, { env: process.env })
      nodes[i].priv.address = res.stdout
    })
  } catch (e) {
    abortClean(`Couldn't get address from private key: ${e}`)
  }

  // finally, get one genesis.json
  const genesis = {}
  try {
    console.error('Getting genesis.json')
    await exec(`${dockerRun} \
      -e TMHOME=/tendermint \
      ${ecr}tendermint:${TM_VERSION} \
      init`, { env: process.env })
    const gen = (await exec(`${dockerRun} \
      busybox \
      cat /tendermint/config/genesis.json`, { env: process.env }))
    Object.assign(genesis, JSON.parse(gen.stdout))
  } catch (e) {
    abortClean(`Could not get genesis.json: ${e}`)
  }

  // add our new nodes
  genesis.validators = nodes.map((node) => {
    return {
      name: node.name,
      'pub_key': node.priv.pub_key,
      power: '10'
    }
  })

  /*
   * Install chaosnodes using helm
   */

  const helmDir = path.join(__dirname, '../', 'helm', 'chaosnode')

  try {
    // install a chaosnode
    await asyncForEach(nodes, async (node, i) => {


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

      console.error(`Installing ${node.name}`)
      // create a string of peers
      const peerIds = []
      const peers = nodes.map((peer) => {
        if (peer.name === node.name) { return null }
        peerIds.push(peer.priv.address)
        return `${peer.priv.address}@${masterIP}:${peer.port.p2p}`
      }).filter((el) => el !== null).join(',')
      await exec(`helm install --name ${node.name} ${helmDir} \
        --set genesis=${str2b64(JSON.stringify(genesis))}\
        --set privValidator=${str2b64(JSON.stringify(node.priv))}\
        --set nodeKey=${str2b64(JSON.stringify(node.nodeKey))}\
        --set tendermint.persistentPeers="${str2b64(peers)}" \
        --set tendermint.privatePeerIds="${str2b64(peerIds.join(','))}" \
        --set tendermint.nodePorts.enabled=true \
        --set tendermint.nodePorts.p2p=${node.port.p2p} \
        --set tendermint.nodePorts.rpc=${node.port.rpc} \
        --set tendermint.moniker=${node.name} \
        --set chaosnode.image.tag=${VERSION_TAG} \
        --set tendermint.image.tag=${TM_VERSION} \
        --set noms.image.tag=${NOMS_VERSION} \
        ${toxiSettings} \
        ${envSpecificHelmOpts} \
      `, { env: process.env })
    })
  } catch (e) {
    abortClean(`Could not install with helm: ${e}`)
  }

  Promise.all([
    clean(),
    saveLogs({ nodes, genesis, masterIP })
  ])
    .then(() => console.error('All done'))
    .catch((e) => console.error(`Couldn't finish: ${e}`))
}

main()

// saveLogs writes a log to a directory
function saveLogs (finalConfig) {
  let timestamp = new Date().toISOString()
    .replace(/T/g, '_')
    .replace(/:/g, '-')
    .replace(/\..+/, '')

  let logConfigFile = `chaos-config-${timestamp}.json`

  console.error(`Config log saved to: ${logConfigFile}`)
  return writeFile(path.join(__dirname, logConfigFile), JSON.stringify(finalConfig, null, 2))
}
