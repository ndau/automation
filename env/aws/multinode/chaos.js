#!/usr/bin/env node

// This script deploys new chaos nodes in a two node network.

const fs = require('fs')
const util = require('util')
const exec = util.promisify(require('child_process').exec)
const readFile = util.promisify(fs.readFile)
const path = require('path');


const asyncForEach = async function(a, cb) {
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
  if (process.argv.length < 4) {
    console.log(`
    Please supply a port to start and some node names.
    Usage
    ./chaos.js 30000 phobos deimos
    `)
    process.exit(1)
  }

  // get the starting port from the arguments
  portCount = parseInt(process.argv[2])

  // get node names from arguments
  const nodeNames = []
  process.argv.forEach((val, i) => {
    if (i > 2) {
      newNode(val)
    }
  })

  // generate two validators
  try {
    await asyncForEach(nodes, async (node, i ) => {
      let res = await exec("tendermint gen_validator")
      nodes[i].priv = JSON.parse(res.stdout)
    })
  } catch (e) {
    console.log(`Tendermint could not generate validators: ${e}`)
    process.exit(1)
  }

  // generate genesis.json (et al)
  try {
    await exec("tendermint init", {env:{TMHOME:"./tmp", PATH:process.env.PATH}})
  } catch (e) {
    console.log(`Could not init tendermint: ${e}`)
    process.exit(1)
  }

  // Get the newly created genesis
  const genesis = {}
  try {
    Object.assign(genesis, JSON.parse(await readFile("./tmp/config/genesis.json",{encoding: 'utf8'})))
  } catch(e) {
    console.log(`Could not init tendermint: ${e}`)
    process.exit(1)
  }

  // add our new nodes
  genesis.validators = nodes.map( (node) => {
    return {
      name: node.name,
      'pub_key' : node.priv.pub_key,
      power: 10
    }
  })

  // Install chaosnodes using helm

  const helmDir = path.join(__dirname, '../../..', 'helm', 'chaosnode')

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

    // install a chaosnode
    await asyncForEach(nodes, async (node) => {
      let cmd = `helm install --name ${node.name} ${helmDir} \
        --set genesis=${str2b64(JSON.stringify(genesis))}\
        --set privValidator=${str2b64(JSON.stringify(node.priv))}\
        --set persistentPeers="${str2b64(peers)}" \
        --set p2pPort=${node.port.p2p} \
        --set rpcPort=${node.port.rpc} \
        --set tendermint.moniker=${node.name} \
        --tls
      `
      console.log(cmd)
      await exec(cmd)
    })

  } catch (e) {
    console.log(`Could not install with helm: ${e}`)
    process.exit(1)
  }

  let logConfigFile = `chaos-config-${new Date().toISOString().
    replace(/T/g, '_').
    replace(/\:/g, '-').
    replace(/\..+/, '')}.json`

  let finalConfig = {
    nodes: nodes,
    peers: peers
  }

  console.log(`Your nodes are configured as follows:\n${JSON.stringify(finalConfig, null, 2)}`)
  console.log(`on ${masterIP}`)
  console.log(`config log saved to: ${logConfigFile}`)
  fs.writeFile(path.join(__dirname, logConfigFile), JSON.stringify(finalConfig, null, 2), ()=>{})

}

main()
