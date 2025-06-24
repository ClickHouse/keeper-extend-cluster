# Sandbox to upgrade a single node keeper to a cluster

## Preparation

The docker-compose starts the containers with the same user ID as the current user. To do it, `UID` and `GID` environment variables should be added to `.env`:

```
$ make prepare
# Or, to clean and create it
$ make reset
```

### Reset the progress, clean up everything

If at any stage you need to clean up the state, just run the following from the repository's root:

```
$ make reset
```

## Stage 1: single node keeper and its client

The default set of docker-compose services has two services: `zoo1` and `clickhouse`:

```
# Run clickhouse and zoo1 containers
$ docker compose up -d
[+] Running 3/3
 ✔ Network keeper-cluster_keeper-cluster  Created   0.1s
 ✔ Container keeper-cluster-zoo1-1        Started   0.5s
 ✔ Container keeper-cluster-clickhouse-1  Started   0.7s
```

At this stage, the `clickhouse-server` nodes are connected to `zoo1` and has a ReplicatedMergeTree table `default.test_replication`

```
$ docker compose exec clickhouse1 clickhouse-client -q 'SELECT * FROM test_replication'
1
2
$ docker compose exec clickhouse2 clickhouse-client -q 'SELECT * FROM test_replication'
1
2
```

And `zoo1` node has `clickhouse` "directory" in it's root:

```
$ docker compose exec zoo1 clickhouse-keeper-client -q 'ls "/"'
clickhouse keeper
```

## Stage 2: adding a second node to the keeper cluster:

> Attention!  
> One should never add more nodes than existing currently in the cluster. In this case, they will decide to make a new cluster.

Now, when everything works, let's add a second node:

```
$ docker compose --profile keeper-extend up -d
[+] Running 3/3
 ✔ Container keeper-cluster-zoo2-1        Started   0.4s
 ✔ Container keeper-cluster-zoo1-1        Running   0.0s
 ✔ Container keeper-cluster-clickhouse-1  Running   0.0s
```

`zoo2` is unknown to `zoo1`. It can't join the cluster and does not work:

```
$ docker compose exec zoo2 clickhouse-keeper-client -q 'ls "/"'
Coordination::Exception: All connection tries failed while connecting to ZooKeeper. nodes: [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181

```

And we have the next lines in a log:

```
$ grep deny -C10 data/zoo1/clickhouse-keeper.log
........
2024.05.14 13:23:44.983985 [ 35 ] {} <Information> RaftInstance: receive a incoming rpc connection
2024.05.14 13:23:44.984019 [ 35 ] {} <Information> RaftInstance: session 1 got connection from ::ffff:172.24.0.4:48888 (as a server)
2024.05.14 13:23:44.984058 [ 35 ] {} <Trace> RaftInstance: asio rpc session created: 0x7eb9daab4018
2024.05.14 13:23:44.984109 [ 36 ] {} <Debug> RaftInstance: Receive a pre_vote_request message from 2 with LastLogIndex=0, LastLogTerm 0, EntriesLength=0, CommitIndex=0 and Term=0
2024.05.14 13:23:44.984136 [ 36 ] {} <Information> RaftInstance: [PRE-VOTE REQ] my role leader, from peer 2, log term: req 0 / mine 3
last idx: req 0 / mine 67, term: req 0 / mine 3
HB alive
2024.05.14 13:23:44.984145 [ 36 ] {} <Information> RaftInstance: pre-vote decision: XX (strong deny, non-existing node)
2024.05.14 13:23:44.984154 [ 36 ] {} <Debug> RaftInstance: Response back a pre_vote_response message to 2 with Accepted=0, Term=0, NextIndex=18446744073709551615
........
```


We need to add the new server to a known one. To make it possible, the config parameter `clickhouse.keeper_server.enable_reconfiguration=true` should be set, see [keeper_single.xml](configs/keeper_single.xml) and [keeper_cluster.xml](configs/keeper_cluster.xml).

Now, to add it, run the next command on the `zoo1` node:

```
$ docker compose exec zoo1 clickhouse-keeper-client -q 'reconfig ADD "server.2=zoo2:9234"'
server.2=zoo2:9234;participant;1
server.1=zoo1:9234;participant;1
```

The next lines will be in the `zoo1` log:

```
$ grep 'Add server' -C10 data/zoo1/clickhouse-keeper.log
2024.05.14 13:24:07.224522 [ 24 ] {} <Debug> RaftInstance: append at log_idx 74, timestamp 1715693047224499
2024.05.14 13:24:07.242767 [ 46 ] {} <Debug> RaftInstance: commit upto 74, current idx 73
2024.05.14 13:24:07.242838 [ 46 ] {} <Trace> RaftInstance: commit upto 74, current idx 74
2024.05.14 13:24:07.242890 [ 46 ] {} <Debug> RaftInstance: DONE: commit upto 74, current idx 74
2024.05.14 13:24:08.778083 [ 36 ] {} <Debug> RaftInstance: Receive a pre_vote_request message from 2 with LastLogIndex=0, LastLogTerm 0, EntriesLength=0, CommitIndex=0 and Term=0
2024.05.14 13:24:08.778122 [ 36 ] {} <Information> RaftInstance: [PRE-VOTE REQ] my role leader, from peer 2, log term: req 0 / mine 3
last idx: req 0 / mine 74, term: req 0 / mine 3
HB alive
2024.05.14 13:24:08.778128 [ 36 ] {} <Information> RaftInstance: pre-vote decision: XX (strong deny, non-existing node)
2024.05.14 13:24:08.778134 [ 36 ] {} <Debug> RaftInstance: Response back a pre_vote_response message to 2 with Accepted=0, Term=0, NextIndex=18446744073709551615
2024.05.14 13:24:09.240087 [ 24 ] {} <Debug> KeeperDispatcher: Processing config update (Add server 2): pushed
2024.05.14 13:24:09.240159 [ 48 ] {} <Debug> RaftInstance: Receive a add_server_request message from 0 with LastLogIndex=0, LastLogTerm 0, EntriesLength=1, CommitIndex=0 and Term=0
2024.05.14 13:24:09.240336 [ 48 ] {} <Information> RaftInstance: sent join request to peer 2, zoo2:9234
2024.05.14 13:24:09.240347 [ 48 ] {} <Debug> RaftInstance: Response back a add_server_response message to 1 with Accepted=1, Term=3, NextIndex=75
2024.05.14 13:24:09.240356 [ 48 ] {} <Debug> KeeperDispatcher: Processing config update (Add server 2): accepted
2024.05.14 13:24:09.241586 [ 32 ] {} <Information> RaftInstance: 0x7eb9d9676018 connected to zoo2:9234 (as a client)
2024.05.14 13:24:09.258657 [ 33 ] {} <Debug> RaftInstance: type: 13, err 0
2024.05.14 13:24:09.258703 [ 33 ] {} <Debug> RaftInstance: Receive an extended join_cluster_response message from peer 2 with Result=1, Term=0, NextIndex=1
2024.05.14 13:24:09.258719 [ 33 ] {} <Information> RaftInstance: new server (2) confirms it will join, start syncing logs to it
2024.05.14 13:24:09.258732 [ 33 ] {} <Debug> RaftInstance: [SYNC LOG] peer 2 start idx 1, my log start idx 1
2024.05.14 13:24:09.258745 [ 33 ] {} <Information> RaftInstance: [SYNC LOG] LogSync is done for server 2 with log gap 73 (74 - 1, limit 99999), now put the server into cluster
2024.05.14 13:24:09.266283 [ 46 ] {} <Debug> RaftInstance: commit upto 75, current idx 74
2024.05.14 13:24:09.266348 [ 46 ] {} <Trace> RaftInstance: commit upto 75, current idx 75
2024.05.14 13:24:09.266361 [ 46 ] {} <Information> RaftInstance: config at index 75 is committed, prev config log idx 64
2024.05.14 13:24:09.266377 [ 46 ] {} <Information> RaftInstance: new config log idx 75, prev log idx 64, cur config log idx 64, prev log idx 63
```

And `zoo2` works now:

```
$ docker compose exec zoo2 clickhouse-keeper-client -q 'ls "/"'
clickhouse keeper
```

## Stage 3: add a third node

Now, we need to do the same with the `zoo3` node

```
$ docker compose --profile keeper-cluster up -d
[+] Running 4/4
 ✔ Container keeper-cluster-zoo2-1        Running   0.0s
 ✔ Container keeper-cluster-zoo3-1        Started   0.4s
 ✔ Container keeper-cluster-zoo1-1        Running   0.0s
 ✔ Container keeper-cluster-clickhouse-1  Running   0.0s
$ docker compose exec zoo1 clickhouse-keeper-client -q 'reconfig ADD "server.3=zoo3:9234"'
server.3=zoo3:9234;participant;1
server.1=zoo1:9234;participant;1
server.2=zoo2:9234;participant;1
$ docker compose exec zoo3 clickhouse-keeper-client -q 'ls "/"'
clickhouse keeper
```

## Check the cluster works after restart

To restart the cluster, just run the next command:

```
$ docker compose --profile keeper-cluster restart
```

And let's check the status of keeper nodes:

```
$ for id in {1..3}; do echo zoo${id}; docker compose exec zoo${id} clickhouse-keeper-client -q 'stat' | grep Mode; done
zoo1
Mode: follower
zoo2
Mode: follower
zoo3
Mode: leader
```

## Remaining steps

In real world, there are few more things to do:

- Update the [zookeeper.xml](configs/zookeeper.xml) configuration by adding new nodes there. The `clickhouse-server` must restart to apply zookeeper configuration.
- Update the [keeper_single.xml](configs/keeper_single.xml) config by adding there two new nodes.

