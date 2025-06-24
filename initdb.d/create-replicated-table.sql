SELECT sleep(3); -- wait for keeper
CREATE TABLE default.test_replication (val String) ENGINE=ReplicatedMergeTree('/clickhouse/tables/test_replication', '{replica}') PRIMARY KEY val;

-- Insert every one replica number into the default.test_replication
INSERT INTO default.test_replication SELECT replica_num FROM system.clusters WHERE host_name == hostName();
