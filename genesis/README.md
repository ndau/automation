# make genesis snapshot

This script will start docker containers that will be used to create the first snapshot.

It uses the genesis and generate tool, both of which you must install with the following commands:

```
go get github.com/oneiro-ndev/chaos_genesis
cd $GOPATH/github.com/oneiro-ndev/chaos_genesis
glide install
cd $GOPATH/src/github.com/oneiro-ndev/chaos_genesis/cmd/generate
go install .
cd $GOPATH/src/github.com/oneiro-ndev/chaos_genesis/cmd/genesis
go install .
```

# upload new snapshot

This script will compress the contents of each noms database and upload it to s3.
