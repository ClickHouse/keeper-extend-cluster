SELECT sleep(3); -- wait for keeper
CREATE TABLE default.test_repliacation (val String) ENGINE=ReplicatedMergeTree('/clickhouse/tables/test_replication', '{replica}') PRIMARY KEY val;

-- Insert every one replica number into the default.test_repliacation
INSERT INTO default.test_repliacation SELECT replica_num FROM system.clusters WHERE host_name == hostName();
