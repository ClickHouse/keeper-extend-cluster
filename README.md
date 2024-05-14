```
# Run all containers as a current user
$ export UID=$UID
# clean every state, and start from the scratch
$ git clean -fxd data/
$ docker compose --profile keeper-cluster down --remove-orphans

# Run clickhouse and zoo1 containers
$ docker compose up -d
# Let's check that it works. clickhouse-client should return the next data
$ docker exec -it keeper-cluster-clickhouse-1 clickhouse-client -q 'SELECT * FROM test_repliacation'
1
2
$ docker exec -it keeper-cluster-zoo1-1 clickhouse-keeper-client -q 'ls /'
clickhouse keeper

# After everything is created in the zoo1, let's add zoo2
# ATTENTION: we should not add at the same time number of nodes that could have a quorum
# Now we have a single node, so two nodes added at a moment will decide that one of them is the leader
$ docker compose --profile keeper-extend up -d
# Now, zoo2 is unknown to zoo1. It can't join the cluster and does not work
$ docker exec -it keeper-cluster-zoo2-1 clickhouse-keeper-client -q 'ls /'
Coordination::Exception: All connection tries failed while connecting to ZooKeeper. nodes: [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181
Poco::Exception. Code: 1000, e.code() = 111, Connection refused (version 24.4.1.2088 (official build)), [::1]:9181

# And we have there the next lines in a log:
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

# We need to add the server to a known. To do it,
# the config parameter clickhouse.keeper_server.enable_reconfiguration=true should be set
$ docker exec -it keeper-cluster-zoo1-1 clickhouse-keeper-client -q 'reconfig ADD "server.2=zoo2:9234"'
server.2=zoo2:9234;participant;1
server.1=zoo1:9234;participant;1
# The next lines will be in the zoo1 log
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

# And after that zoo2 works
$ docker exec -it keeper-cluster-zoo2-1 clickhouse-keeper-client -q 'ls /'
clickhouse keeper

# Now, we need to do the same to the zoo3
$ docker compose --profile keeper-cluster up -d
$ docker exec keeper-cluster-zoo1-1 clickhouse-keeper-client -q 'reconfig ADD "server.3=zoo3:9234"'
server.3=zoo3:9234;participant;1
server.1=zoo1:9234;participant;1
server.2=zoo2:9234;participant;1
$ docker exec -it keeper-cluster-zoo3-1 clickhouse-keeper-client -q 'ls /'
clickhouse keeper

# That's it, the cluster could be restarted
$ docker compose --profile keeper-cluster restart
# And let's check the staus of ZK nodes
$ for id in {1..3}; do echo zoo${id}; docker exec -t keeper-cluster-zoo${id}-1 bash -c 'echo stat | nc localhost 9181 | grep Mode'; done
zoo1
Mode: follower
zoo2
Mode: follower
zoo3
Mode: leader

# Don't forget to update the clickhouse.zookeeper parameter by adding there new nodes
```
