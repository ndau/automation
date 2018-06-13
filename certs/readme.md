# Setting up helm

Create signing certificate authority

> Note: On a mac I had to append the following in my `/usr/local/etc/openssl/openssl.cnf` file and reference the config file specifically in my command.

```
[ v3_ca ]
basicConstraints = critical,CA:TRUE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
```

```
$ openssl req -key ca.key.pem -new -x509 -days 7300 -sha256 -out ca.cert.pem -extensions v3_ca -config /usr/local/etc/openssl/openssl.cnf
```


Create a key and certificate for the server
```
$ openssl genrsa -out ./tiller.key.pem 4096
$ openssl req -key tiller.key.pem -new -sha256 -out tiller.csr.pem
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) []:US
State or Province Name (full name) []:MA
Locality Name (eg, city) []:Boston
Organization Name (eg, company) []:Ndev
Organizational Unit Name (eg, section) []:
Common Name (eg, fully qualified host name) []:dev-chaos-tiller-server
Email Address []:

Please enter the following 'extra' attributes
to be sent with your certificate request
A challenge password []:
```

Create a key and certificate for the client (each user should have their own ideally).
```
$ openssl genrsa -out ./helm.key.pem 4096
$ openssl req -key helm.key.pem -new -sha256 -out helm.csr.pem
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) []:US
State or Province Name (full name) []:MA
Locality Name (eg, city) []:Boston
Organization Name (eg, company) []:Ndev
Organizational Unit Name (eg, section) []:Infrastructure/Machine users
Common Name (eg, fully qualified host name) []:infrastructure-machine-users
Email Address []:

Please enter the following 'extra' attributes
to be sent with your certificate request
A challenge password []:
```

Sign the certs.

```
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in tiller.csr.pem -out tiller.cert.pem -days 365
Signature ok
subject=/C=US/ST=MA/L=Boston/O=Ndev/CN=dev-chaos-tiller-server
Getting CA Private Key
openssl x509 -req -CA ca.cert.pem -CAkey ca.key.pem -CAcreateserial -in helm.csr.pem -out helm.cert.pem  -days 365
```




Installing the helm tool on your machine

```
brew install kubernetes-helm
```

Installing the helm tiller on your kubernetes cluster

```
helm init --tiller-tls --tiller-tls-cert ./tiller.cert.pem --tiller-tls-key ./tiller.key.pem --tiller-tls-verify --tls-ca-cert ca.cert.pem
```

Upgrade the `kube-system:default` service account with the cluster-admin role. [See issue.](https://github.com/kubernetes/helm/issues/2687)

```
kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:default
```

Copy certs to Helm's config dir

```
cp ca.cert.pem $(helm home)/ca.pem
cp helm.cert.pem $(helm home)/cert.pem
cp helm.key.pem $(helm home)/key.pem
```

To test, running this command should not error

```
helm ls --tls
```
