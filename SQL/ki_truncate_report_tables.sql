TRUNCATE TABLE rpt_airframe_kd;
TRUNCATE TABLE rpt_airframe_sortie;
TRUNCATE TABLE rpt_airframe_stats;
TRUNCATE TABLE rpt_airframe_weapon;
TRUNCATE TABLE rpt_overall_server_traffic;
TRUNCATE TABLE rpt_overall_stats;

INSERT INTO raw_connection_log
SELECT * FROM backup_connection_log;

TRUNCATE TABLE backup_connection_log;