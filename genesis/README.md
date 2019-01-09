# nodegroup.sh

This script will start docker containers that will be used to create the genesis snapshot. Running the script will snapshot the noms databases, tendermint databases, svi-namespace and update the latest.txt file.

## dependencies

nodegroup.sh uses the genesis tool, both of which you must install with the following commands:

```shell
go get github.com/oneiro-ndev/commands
cd $GOPATH/github.com/oneiro-ndev/commands
go dep ensure
cd $GOPATH/src/github.com/oneiro-ndev/commands/cmd/generate
go install .
cd $GOPATH/src/github.com/oneiro-ndev/commands/cmd/genesis
go install .
```

Once the generate tool is installed, it must be run and the output moved to `assc.toml` and `genesis.toml` in the `automation/genesis` directory.

## arguments

_`use -h` for a complete list of options._

The first argument is the name of the "release", meaning its data directories will be contained in a directory named `rel-RELEASE`. The second argument is the starting port, meaning containers that expose ports will be assigned ports in a sequential manner starting from that number.

## examples

```
# Start up docker containers, initialize tendermint and quit.
# ./nodegroup dev 10000 --tendermint-init
./nodegroup dev 10000 -t

# Start up docker containers, go though genesis, then quit.
# ./nodegroup dev 10000 --genssis
./nodegroup dev 10000 -g


# Start up docker containers, go though genesis, then leave it running until a key is pressed.
# ./nodegroup dev 10000 --genesis --run
./nodegroup dev 10000 -g -r

# Start up docker containers, go though genesis, then leave it running until a key is pressed, make a snapshot, and upload it to s3.
./nodegroup dev 10000 -g -r -s -u

```

# docker running conventions

In the example below there are several options set.

```
docker run -d \
	--name="$container_name" \
	-e NDAUHOME="$NDAU_HOME" \
	-w "$NDAU_HOME" \
	-p $NDAU_ABCI_PORT:$NDAU_ABCI_PORT \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
		-index $NDAU_REDIS_ADDR \
		-addr 0.0.0.0:$NDAU_ABCI_PORT \
		-spec http://$IH:$NDAU_NOMS_PORT
```

* `$container_name` is there so the name can be added to an array of container names to clean up at the end of this script's execution. `trap clean EXIT`
* `-e NDAUHOME="$NDAU_HOME"` sets an environment variable accessible inside the container.
* `-w "$NDAU_HOME"` sets the current working directory for when the container starts.
* `-p $NDAU_ABCI_PORT:$NDAU_ABCI_PORT` binds the host's port to the container's port.
* `--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind` simply shares our local directory specified with `$NDAU_HOME` and makes it available at the same path within the container.
* `$NDAU_IMAGE` This is the name of the docker image that is actually going to run.
The rest of the options are for the ndau image itself.

_Docker gotchas_

### Internal Host (IH)

Inside a docker container, containers can contact each other via ports that are exposed using the `-p` option. However, localhost refers specifically to that container. The docker's virtual machine has a network interface that is assigned a local subnet IP. That IP address is reassigned at some interval. The convoluted line `$(docker run busybox ip route | awk '/default/ { print $3 }')` is the way to get that value.

### Entrypoint command arguments

If you're trying to use a different entrypoint than the one specified in the image's dockerfile, you have to use an odd argument sequence. This is how your command should look: `docker run --entrypoint "/bin/ls" $NDAU_IMAGE -al /root/config` This starts the $NDAU_IMAGE and executes `/bin/ls -al /root/config`. Little weird, huh? LFMF.
