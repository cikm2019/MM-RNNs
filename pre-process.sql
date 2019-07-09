set search_path to mimic3;
--filter out patient ( 16<=x<=75 ) base on requirement.
CREATE MATERIALIZED VIEW mimic3.mt1_patients_adults AS 
 SELECT p.subject_id,
    icu.icustay_id,
    icu.hadm_id,
    p.gender,
    icu.dbsource,
    icu.first_careunit,
    icu.last_careunit,
    icu.first_wardid,
    icu.last_wardid,
    icu.intime,
    icu.outtime,
    icu.los,
    date_part('year'::text, icu.intime) - date_part('year'::text, p.dob) AS pt_age
   FROM mimic3.patients p,
    mimic3.icustays icu
	WHERE p.subject_id = icu.subject_id 
		AND (date_part('year'::text, icu.intime) - date_part('year'::text, p.dob)) >= 16::double precision	--remove patient younger than 16
		AND (date_part('year'::text, icu.intime) - date_part('year'::text, p.dob)) <=75::double precision	--remove patient older than 75 
		AND icu.los>0.5												--remove patient admined in ICU less than 12hrs
	ORDER BY (date_part('year'::text, icu.intime) - date_part('year'::text, p.dob));
  
CREATE INDEX mt1_patients_adults_idx
  ON mimic3.mimic3.mt1_patients_adults
  USING btree
  (subject_id, hadm_id, icustay_id);

-- filter out data which including,inputevents (careview and metavsion), chartevents, outputevents) base on for fillted patient(mimic3.mt1_inputevents_cv_adults)
-- input event of careview
CREATE OR REPLACE VIEW mimic3.mt1_inputevents_cv_adults AS 
SELECT cv.row_id,
    cv.subject_id,
    cv.hadm_id,
    cv.icustay_id,
    cv.charttime,
    cv.itemid,
    cv.amount,
    cv.amountuom,
    cv.rate,
    cv.rateuom,
    cv.storetime,
    cv.cgid,
    cv.orderid,
    cv.linkorderid,
    cv.stopped,
    cv.newbottle,
    cv.originalamount,
    cv.originalamountuom,
    cv.originalroute,
    cv.originalrate,
    cv.originalrateuom,
    cv.originalsite
   FROM mimic3.inputevents_cv cv
  WHERE (cv.subject_id IN ( 
	SELECT DISTINCT mt1_patients_adults.subject_id
           FROM mimic3.mt1_patients_adults));
           
-- input event of metavision
CREATE OR REPLACE VIEW mimic3.mt1_inputevents_mv_adults AS 
 SELECT mv.row_id,
    mv.subject_id,
    mv.hadm_id,
    mv.icustay_id,
    mv.starttime,
    mv.endtime,
    mv.itemid,
    mv.amount,
    mv.amountuom,
    mv.rate,
    mv.rateuom,
    mv.storetime,
    mv.cgid,
    mv.orderid,
    mv.linkorderid,
    mv.ordercategoryname,
    mv.secondaryordercategoryname,
    mv.ordercomponenttypedescription,
    mv.ordercategorydescription,
    mv.patientweight,
    mv.totalamount,
    mv.totalamountuom,
    mv.isopenbag,
    mv.continueinnextdept,
    mv.cancelreason,
    mv.statusdescription,
    mv.comments_editedby,
    mv.comments_canceledby,
    mv.comments_date,
    mv.originalamount,
    mv.originalrate
   FROM mimic3.inputevents_mv mv
  WHERE (mv.subject_id IN ( 
	SELECT DISTINCT mt1_patients_adults.subject_id
           FROM mimic3.mt1_patients_adults));
           
--chartevents
CREATE OR REPLACE VIEW mimic3.mt1_chartevents_adults AS 
 SELECT c.row_id,
    c.subject_id,
    c.hadm_id,
    c.icustay_id,
    c.itemid,
    c.charttime,
    c.storetime,
    c.cgid,
    c.value,
    c.valuenum,
    c.valueuom,
    c.warning,
    c.error,
    c.resultstatus,
    c.stopped
   FROM mimic3.chartevents c
  WHERE (c.subject_id IN ( SELECT DISTINCT mt1_patients_adults.subject_id
           FROM mimic3.mt1_patients_adults));
           
--outputtvents
CREATE OR REPLACE VIEW mimic3.mt1_outputevents_adults AS 
 SELECT o.row_id,
    o.subject_id,
    o.hadm_id,
    o.icustay_id,
    o.charttime,
    o.itemid,
    o.value,
    o.valueuom,
    o.storetime,
    o.cgid,
    o.stopped,
    o.newbottle,
    o.iserror
   FROM mimic3.outputevents o
  WHERE (o.subject_id IN ( SELECT DISTINCT mt1_patients_adults.subject_id
           FROM mimic3.mt1_patients_adults));
           
---to get a paitent`s daily urine output.
CREATE MATERIALIZED VIEW mimic3.mt1_adults_daily_urine_outputs AS 
 SELECT mt1_adults_sofa_vars_tw.icustay_id,
    mt1_adults_sofa_vars_tw.tw_24hr,
    sum(mt1_adults_sofa_vars_tw.valuenum) AS urine_output_per_24hrs
   FROM mimic3.mt1_adults_sofa_vars_tw
  WHERE lower(mt1_adults_sofa_vars_tw.itemcat) = 'urine'::text
  GROUP BY mt1_adults_sofa_vars_tw.icustay_id, mt1_adults_sofa_vars_tw.tw_24hr
WITH DATA;

CREATE INDEX idx01_mt1_adults_daily_urine_outputs
  ON mimic3.mt1_adults_daily_urine_outputs
  USING btree
  (icustay_id);
  
--labevents 
CREATE VIEW mimic3.mt1_labevents_adults AS 
 SELECT l.subject_id,
    l.hadm_id,
    i.icustay_id,
    l.itemid,
    l.charttime,
    i.intime,
    i.outtime,
    l.value,
    l.valuenum,
    l.valueuom,
    l.flag
   FROM mimic3.labevents l,
	mimic3.icustays i
  WHERE i.hadm_id = l.hadm_id 
           AND (date_part('epoch'::text, l.charttime) - date_part('epoch'::text, i.intime)) >= '-3600'::integer::double precision 
           AND (date_part('epoch'::text, i.outtime) - date_part('epoch'::text, l.charttime)) >= '-3600'::integer::double precision
           ORDER BY l.charttime;
           
--organise GCS using (SEN`s Code)

CREATE OR REPLACE VIEW mimic3.mt1_adults_gcs AS 
 SELECT tmp.subject_id,
    tmp.hadm_id,
    tmp.icustay_id,
    'GCS'::text AS itemcat,
    tmp.charttime,
    tmp.cvalue,
    tmp.valuenum,
    tmp.valueuom
   FROM ( SELECT DISTINCT c.row_id,
            c.subject_id,
            c.hadm_id,
            c.icustay_id,
            'GCS'::text AS itemcat,
            c.charttime,
            c.value AS cvalue,
            c.valuenum,
            c.valueuom
           FROM mimic3.mt1_chartevents_adults as c
          WHERE c.itemid = 198
          ORDER BY c.subject_id, c.hadm_id, c.icustay_id, c.charttime) tmp
UNION ALL
 SELECT tmp.subject_id,
    tmp.hadm_id,
    tmp.icustay_id,
    'GCS'::text AS itemcat,
    tmp.charttime,
    to_char(sum(tmp.val), 'FM99'::text) AS cvalue,
    sum(tmp.val) AS valuenum,
    'points'::character varying AS valueuom
   FROM ( SELECT DISTINCT c.row_id,
            c.subject_id,
            c.hadm_id,
            c.icustay_id,
            c.charttime,
            c.valuenum AS val
           FROM mimic3.mt1_chartevents_adults c
          WHERE c.itemid = ANY (ARRAY[220739, 223900, 223901])
          ORDER BY c.charttime) tmp
  GROUP BY tmp.charttime, tmp.subject_id, tmp.hadm_id, tmp.icustay_id
  ORDER BY 1, 2, 5;

 --organise SOFA feature to estimate SOFA score SOFA features including, PaO2/FlO2 SaO2/FLO2, Platelets, Bilirubin, Hypotension, Glasgow Comma, Creatinine/Urineoutput
 --filter out ABP, Bilirubin, Creatinine, PaOs Platelets (chartevents)
CREATE MATERIALIZED VIEW mimic3.mt1_adults_sofa_vars AS 
SELECT c.subject_id,
    c.hadm_id,
    c.icustay_id,
        CASE
            WHEN c.itemid = ANY (ARRAY[52, 456, 220181, 220052, 225312]) THEN 'ABP_mean'::text
            WHEN c.itemid = ANY (ARRAY[848, 1538, 225690]) THEN 'Bilirubin'::text
            WHEN c.itemid = ANY (ARRAY[791, 220615]) THEN 'CREATININE'::text
            WHEN c.itemid = ANY (ARRAY[779, 220224]) THEN 'PaO2'::text
            WHEN c.itemid = ANY (ARRAY[828, 227457]) THEN 'Platelets'::text
            --apachii
            WHEN c.itemid = ANY (ARRAY[780, 1126, 223830]) THEN 'Arterial_pH'::text
            WHEN c.itemid = ANY (ARRAY[812, 227443]) THEN 'HCO3'::text
            WHEN c.itemid = ANY (ARRAY[813, 220545]) THEN 'HCT'::text
            WHEN c.itemid = ANY (ARRAY[211, 220045]) THEN 'HR'::text
            WHEN c.itemid = ANY (ARRAY[778, 220235]) THEN 'PaCO2'::text
            WHEN c.itemid = ANY (ARRAY[829, 1535, 227442, 227464]) THEN 'POTASSIUM'::text
            WHEN c.itemid = ANY (ARRAY[615, 618, 224688, 220210, 224690, 224689]) THEN 'RR'::text
            WHEN c.itemid = ANY (ARRAY[837, 1536, 220645, 226534]) THEN 'SODIUM'::text
            WHEN c.itemid = ANY (ARRAY[861, 1127, 1542, 220546]) THEN 'WBC'::text
            --saps
            WHEN c.itemid = ANY (ARRAY[51, 455, 220050, 220179]) THEN 'ABP_systolic'::text
            WHEN c.itemid = ANY (ARRAY[781, 1162, 225624]) THEN 'BUN'::text
            ELSE NULL::text
        END AS itemcat,
    c.itemid,
    c.charttime,
    c.value AS cvalue,
    c.valuenum,
    c.valueuom
   FROM mimic3.mt1_chartevents_adults c
	WHERE (c.itemid = ANY (ARRAY[51,52,211,455,456,615,618,778,779,780,781,791,
	812,813,829,837,848,861,1126,1127,1162,1535,1536,1538,1542,220045,220050,
	220052,220179,220181,220210,220224,220235,220545,220546,220615,220645,
	223830,224688,224689,224690,225312,225624,225690,226534,227442,227443,
	227464])) 
		AND c.valuenum IS NOT NULL 										--remove null
		AND c.valuenum >= 0::double precision 									--remove outrage
		AND c.valuenum <= 3000::double precision 								--remove outrage
		AND (c.hadm_id IN ( SELECT DISTINCT mt1_patients_adults.hadm_id FROM mimic3.mt1_patients_adults)) 	--base on filtered ICU admin

UNION All
--filter out FiO2
 SELECT c.subject_id,
    c.hadm_id,
    c.icustay_id,
    'FiO2'::text AS itemcat,
    c.itemid,
    c.charttime,
        CASE
            WHEN c.valuenum >= 20::double precision AND c.valuenum <= 100::double precision THEN to_char(c.valuenum, 'FM999.999'::text)
            WHEN c.valuenum >= 0.2::double precision AND c.valuenum <= 1::double precision THEN to_char(c.valuenum * 100::double precision, 'FM999.999'::text)
            ELSE NULL::text
        END AS cvalue,
        CASE
            WHEN c.valuenum >= 20::double precision AND c.valuenum <= 100::double precision THEN c.valuenum
            WHEN c.valuenum >= 0.2::double precision AND c.valuenum <= 1::double precision THEN c.valuenum * 100::double precision
            ELSE NULL::double precision
        END AS valuenum,
    '%'::character varying AS valueuom
   FROM mimic3.mimic3.mt1_chartevents_adults c 
	WHERE c.itemid = ANY (ARRAY[189, 190, 223835]) 
	AND c.valuenum IS NOT NULL 										--remove null
	AND c.valuenum >= 0::double precision									--remove outrage
	AND (c.hadm_id IN ( SELECT DISTINCT mt1_patients_adults.hadm_id FROM mimic3.mt1_patients_adults)) 	--base on filtered ICU admin

--filter out Tempeture
UNION ALL
 SELECT c.subject_id,
    c.hadm_id,
    c.icustay_id,
    'TEMP'::text AS itemcat,
    c.itemid,
    c.charttime,
        CASE
            WHEN c.valuenum >= 20::double precision AND c.valuenum <= 50::double precision THEN to_char(c.valuenum, 'FM999.999'::text)
            WHEN c.valuenum >= 68::double precision AND c.valuenum <= 122::double precision THEN to_char((c.valuenum - 32::double precision) * 5::double precision / 9::double precision, 'FM999.999'::text)
            ELSE NULL::text
        END AS cvalue,
        CASE
            WHEN c.valuenum >= 20::double precision AND c.valuenum <= 50::double precision THEN c.valuenum
            WHEN c.valuenum >= 68::double precision AND c.valuenum <= 122::double precision THEN (c.valuenum - 32::double precision) * 5::double precision / 9::double precision
            ELSE NULL::double precision
        END AS valuenum,
    'C'::character varying AS valueuom
   FROM mimic3.chartevents_adults c
  WHERE c.itemid = ANY (ARRAY[676, 677, 678, 679, 223761, 223762])
UNION ALL

--filter out  ABP, Bilirubin, Creatinine, PaOs Platelets (labevents)
SELECT l.subject_id,
    l.hadm_id,
    l.icustay_id,
        CASE
            WHEN l.itemid = 50885 THEN 'Bilirubin'::text
            WHEN l.itemid = 50912 THEN 'CREATININE'::text
            WHEN l.itemid = 50821 THEN 'PaO2'::text
            WHEN l.itemid = 51265 THEN 'Platelets'::text
            --apachii
            WHEN l.itemid = 50820 THEN 'Arterial_pH'::text
            WHEN l.itemid = 50804 THEN 'HCO3'::text
            WHEN l.itemid = ANY (ARRAY[50810, 51221]) THEN 'HCT'::text
            WHEN l.itemid = 50818 THEN 'PaCO2'::text
            WHEN l.itemid = ANY (ARRAY[50971, 50822]) THEN 'POTASSIUM'::text
            WHEN l.itemid = ANY (ARRAY[50983, 50824]) THEN 'SODIUM'::text
            WHEN l.itemid = 51301 THEN 'WBC'::text
	    --saps
            WHEN l.itemid = 51006 THEN 'BUN'::text
            WHEN l.itemid = 51301 THEN 'WBC'::text
            ELSE NULL::text
        END AS itemcat,
    l.itemid,
    l.charttime,
    l.value AS cvalue,
    l.valuenum,
    l.valueuom
   FROM mimic3.mt1_labevents_adults l
	WHERE (l.itemid = ANY (ARRAY[50885, 50912, 50821, 51265, 50820, 50804, 50810, 51221, 50818,
	50971, 50822, 50983, 50824])) 
	AND l.valuenum IS NOT NULL 									--remove null
	AND l.valuenum >= 0::double precision 								--remove outrange
	AND l.valuenum <= 3000::double precision 							--remove outrange
	AND (l.hadm_id IN ( SELECT DISTINCT icustays_adults.hadm_id FROM mimic3.icustays_adults))
UNION ALL
--filter out GCS
SELECT gcs.subject_id,
    gcs.hadm_id,
    gcs.icustay_id,
    gcs.itemcat,
    198 AS itemid,
    gcs.charttime,
    gcs.cvalue,
    gcs.valuenum,
    'points'::character varying AS valueuom
   FROM mimic3.mt1_adults_gcs gcs
  WHERE gcs.valuenum IS NOT NULL AND gcs.valuenum >= 3::double precision
--filter out Dobutamine, Epinephrine, Norepinephrine (careview)
UNION ALL
SELECT cv.subject_id,
    cv.hadm_id,
    cv.icustay_id,
        CASE
            WHEN cv.itemid = 30043 AND cv.rate >= 0::double precision THEN 'Dopamine'::text
            WHEN cv.itemid = ANY (ARRAY[30042, 30306]) THEN 'Dobutamine'::text
            WHEN cv.itemid = ANY (ARRAY[30044, 30119]) THEN 'Epinephrine'::text
            WHEN cv.itemid = ANY (ARRAY[30047, 30120]) THEN 'Norepinephrine'::text
            ELSE NULL::text
        END AS itemcat,
    cv.itemid,
    cv.charttime,
    to_char(cv.rate, 'FM9999.999999'::text) AS cvalue,
    cv.rate AS valuenum,
    cv.rateuom AS valueuom
   FROM mimic3.mt1_inputevents_cv_adults cv
  WHERE (cv.itemid = ANY (ARRAY[30043, 30042, 30306, 30044, 30119, 30047, 30120])) 
  AND cv.rate IS NOT NULL AND cv.rate >= 0::double precision
UNION ALL
--filter out Dobutamine, Epinephrine, Norepinephrine (metavison)
SELECT mv.subject_id,
    mv.hadm_id,
    mv.icustay_id,
        CASE
            WHEN mv.itemid = 221662 AND mv.rate >= 0::double precision THEN 'Dopamine'::text
            WHEN mv.itemid = 221653 THEN 'Dobutamine'::text
            WHEN mv.itemid = 221289 THEN 'Epinephrine'::text
            WHEN mv.itemid = 221906 THEN 'Norepinephrine'::text
            ELSE NULL::text
        END AS itemcat,
    mv.itemid,
    mv.starttime AS charttime,
    to_char(mv.rate, 'FM9999.999999'::text) AS cvalue,
    mv.rate AS valuenum,
    mv.rateuom AS valueuom
   FROM mimic3.inputevents_mv_adults mv
  WHERE (mv.itemid = ANY (ARRAY[221662, 221653, 221289, 221906])) AND mv.rate IS NOT NULL AND mv.rate >= 0::double precision
--filter out urine from all possible input
UNION ALL
 SELECT o.subject_id,
    o.hadm_id,
    o.icustay_id,
    'URINE'::text AS itemcat,
    o.itemid,
    o.charttime,
    to_char(o.value / 1000::double precision, 'FM99999.999999'::text) AS cvalue,
    o.value / 1000::double precision AS valuenum,
    'l'::character varying AS valueuom
   FROM mimic3.outputevents o
  WHERE (o.itemid = ANY (ARRAY[40055, 40056, 40057, 40061, 40065, 40069, 40085, 40094, 40096, 40288, 40405, 40428, 40473, 40715, 43175, 226559])) AND o.value IS NOT NULL AND o.value >= 0::double precision AND o.value <= 10000::double precision AND (o.icustay_id IN ( SELECT 
	mt1_patients_adults.icustay_id
           FROM mimic3.mt1_patients_adults))
WITH DATA;
-- Index
CREATE INDEX idx01_mt1_adults_sofa_vars
  ON mimic3.mt1_adults_sofa_vars
  USING btree
  (subject_id, hadm_id, itemcat COLLATE pg_catalog."default", itemid);

CREATE INDEX idx02_mt1_adults_sofa_vars
  ON mimic3.mt1_adults_sofa_vars
  USING btree
  (subject_id);
CREATE INDEX idx03_mt1_adults_sofa_vars
  ON mimic3.mt1_adults_sofa_vars
  USING btree
  (hadm_id);
CREATE INDEX idx04_mt1_adults_sofa_vars
  ON mimic3.mt1_adults_sofa_vars
  USING btree
  (itemid);
CREATE INDEX idx05_mt1_adults_sofa_vars
  ON mimic3.mt1_adults_sofa_vars
  USING btree
  (itemcat COLLATE pg_catalog."default");
  
-- --organise SOFA between time windows.

 CREATE MATERIALIZED VIEW mimic3.mt1_adults_sofa_vars_tw AS 
 SELECT sofa.subject_id,
    sofa.hadm_id,
    sofa.icustay_id,
    sofa.itemcat,
    sofa.itemid,
    sofa.charttime,
    p.intime,
    p.outtime,
    sofa.cvalue,
    sofa.valuenum,
    sofa.valueuom,
    (date_part('epoch'::text, sofa.charttime) - (date_part('epoch'::text, p.intime) - date_part('minute'::text, p.intime) * 60::double precision - date_part('second'::text, p.intime))) / 3600::double precision AS hour_diff,
    floor(abs(date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) / 3600::double precision) + 1::double precision AS tw_1hr,
    floor(abs(date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) / (3600 * 3)::double precision) + 1::double precision AS tw_3hr,
    floor(abs(date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) / (3600 * 6)::double precision) + 1::double precision AS tw_6hr,
    floor(abs(date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) / (3600 * 12)::double precision) + 1::double precision AS tw_12hr,
    floor(abs(date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) / (3600 * 24)::double precision) + 1::double precision AS tw_24hr
   FROM mimic3.mt1_adults_sofa_vars sofa,
    mimic3.mt1_patients_adults p
  WHERE sofa.subject_id = p.subject_id AND sofa.hadm_id = p.hadm_id 
  AND (date_part('epoch'::text, sofa.charttime) - date_part('epoch'::text, p.intime)) >= '-3600'::integer::double precision 
  AND (date_part('epoch'::text, p.outtime) - date_part('epoch'::text, sofa.charttime)) >= '-3600'::integer::double precision 
  AND sofa.valuenum >= 0::double precision
  ORDER BY sofa.charttime 
WITH DATA;

CREATE INDEX idx1_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (subject_id, hadm_id, itemcat COLLATE pg_catalog."default", itemid);

CREATE INDEX idx2_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (subject_id);

CREATE INDEX idx3_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (hadm_id);

CREATE INDEX idx4_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (itemid);

CREATE INDEX idx5_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (itemcat COLLATE pg_catalog."default");

CREATE INDEX idx6_mt1_adults_sofa_vars_tw
  ON mimic3.mt1_adults_sofa_vars_tw
  USING btree
  (icustay_id, itemcat COLLATE pg_catalog."default", valuenum);

----
--drop table if exists d_sofa1_vars;
CREATE TABLE mimic3.d_sofa1_vars
(
  item_idx integer NOT NULL,
  item_cat text NOT NULL,
  median_value double precision,
  mean_value double precision,
  item_unit text NOT NULL
);

insert into d_sofa1_vars values(1,'ABP_mean',77,79.12687232,'mmHg');
insert into d_sofa1_vars values(2,'Bilirubin',0.9,6.379532751,'mg/dl');
insert into d_sofa1_vars values(3,'CREATININE',1,1.576054889,'mg/dl');
insert into d_sofa1_vars values(4,'Dobutamine',4,5.72484777,'mcg/kg/min');
insert into d_sofa1_vars values(5,'Dopamine',3.998375349,4.588829993,'mcg/kg/min');
insert into d_sofa1_vars values(6,'Epinephrine',0.020014851,0.078062223,'mcg/kg/min');
insert into d_sofa1_vars values(7,'Norepinephrine',0.096969701,0.506031792,'mcg/kg/min');
insert into d_sofa1_vars values(8,'FiO2',40.0000006,49.55805475,'%');
insert into d_sofa1_vars values(9,'GCS',13,12,'points');
insert into d_sofa1_vars values(10,'PaO2',110,134.0670289,'mmHg');
insert into d_sofa1_vars values(11,'Platelets',207,233.4090379,'counts');
insert into d_sofa1_vars values(12,'Urine',80,127.1269676,'ml');
insert into d_sofa1_vars  values(13,'Arterial_pH',7.39,7.394519556,'units');
insert into d_sofa1_vars  values(14,'HCO3',25,25.75305926,'mEq/liter');
insert into d_sofa1_vars  values(15,'HCT',29.5,29.95059522,'%');
insert into d_sofa1_vars  values(16,'HR',86,87.01622922,'BPM');
insert into d_sofa1_vars  values(17,'PaCO2',40,42.08470579,'mmHg');
insert into d_sofa1_vars  values(18,'POTASSIUM',4,4.1234176,'mEq/liter');
insert into d_sofa1_vars  values(19,'RR',19,19.58452559,'breath per minute (bpm)');
insert into d_sofa1_vars  values(20,'SODIUM',139,138.9445677,'mEq/liter');
insert into d_sofa1_vars  values(21,'Temperature',37,37.02296219,'C');
insert into d_sofa1_vars  values(22,'WBC',10.9,12.37677763,'per cubic mm');
insert into d_sofa1_vars  values(23,'ABP_systolic',119,121.0931478,'mmHg');
insert into d_sofa1_vars  values(24,'BUN',24,32.57138594,'mg/dl');
