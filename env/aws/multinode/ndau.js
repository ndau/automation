#!/usr/bin/env node

// This script deploys new ndau nodes in a multiple node network.

const fs = require('fs')
const util = require('util')
const exec = util.promisify(require('child_process').exec)
const readFile = util.promisify(fs.readFile)
const path = require('path');


const asyncForEach = async function (a, cb) {
  for (let i = 0; i < a.length; i++) {
    await cb(a[i], i, a)
  }
}

const str2b64 = (s) => Buffer.from(s).toString('base64')

let portCount = 30000
const newPort = () => portCount++

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

async function main() {
  if (process.argv.length < 4 || process.env.VERSION_TAG === undefined) {
    console.log(`
    Please supply a version tag, a port to start and some node names.
    noms and tendermint versions reflect our container versions, not the applications themselves. They are optional and default to "latest".

    Usage
    [NOMS_VERSION=0.0.1] [TM_VERSION=0.0.1] VERSION_TAG=0.0.1 ./ndau.js 30000 mario luigi
    `)
    process.exit(1)
  }

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
        578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint \
        gen_validator`
      let res = await exec(genValidatorCmd, { env: process.env })
      nodes[i].priv = JSON.parse(res.stdout)
    })
  } catch (e) {
    console.log(`Tendermint could not generate validators: ${e}`)
    process.exit(1)
  }

  // generate genesis.json (et al)
  try {
    // create a volume to save genesis.json
    await exec(`docker volume create genesis`, { env: process.env })
    // run init on our tendermint container
    const initCommand = `docker run \
      --rm \
      -e TMHOME=/tendermint \
      --mount src=genesis,dst=/tendermint \
      578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint \
      init`
    await exec(initCommand, { env: process.env })
  } catch (e) {
    console.log(`Could not init tendermint: ${e}`)
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

  // Install ndaunodes using helm

  const helmDir = path.join(__dirname, '../../..', 'helm', 'ndaunode')

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

    // install a ndaunode
    await asyncForEach(nodes, async (node) => {
      let cmd = `helm install --name ${node.name} ${helmDir} \
        --set genesis=${str2b64(JSON.stringify(genesis))}\
        --set privValidator=${str2b64(JSON.stringify(node.priv))}\
        --set persistentPeers="${str2b64(peers)}" \
        --set p2pNodePort=${node.port.p2p} \
        --set rpcNodePort=${node.port.rpc} \
        --set tendermint.moniker=${node.name} \
        --set chaosnode.image.tag=${VERSION_TAG} \
        --set tendermint.image.tag=${TM_VERSION} \
        --set noms.image.tag=${NOMS_VERSION} \        --tls
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

  let logConfigFile = `ndau-config-${timestamp}.json`

  console.log(`Your nodes are configured as follows:\n${JSON.stringify(finalConfig, null, 2)}`)
  console.log(`config log saved to: ${logConfigFile}`)
  fs.writeFile(path.join(__dirname, logConfigFile), JSON.stringify(finalConfig, null, 2), () => { })

}
