SELECT sleep(3); -- wait for keeper
CREATE TABLE default.test_repliacation (val String) ENGINE=ReplicatedMergeTree('/clickhouse/tables/test_replication', 'clickhouse') PRIMARY KEY val;

INSERT INTO default.test_repliacation VALUES ('1'), ('2');
